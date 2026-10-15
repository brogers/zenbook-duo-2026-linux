// powermonitor: QML plugin behind the "Zenbook Duo Power" panel widget.
//
// Reads everything straight from sysfs (a few small files per sample, no helper processes).
// The widget sets the sampling interval: slow while it only shows the number in the panel,
// faster while its popup is open.
//
// What the laptop draws: the RAPL "psys" platform energy counter. It integrates the
// charger's system power monitor (PSYS), which measures the power going into the laptop
// from the charger input and the battery together, without the power that goes into the
// battery: stopping the charge at a fixed load leaves it unchanged. So it is valid on AC
// and on battery alike. On this model it reads about twice the real value (the BIOS gain
// does not match the charger's), so it is scaled; the widget refines the scale on battery,
// where psys must equal the battery's discharge power.
//
// The battery's flow: BAT0 power_now is |current| x DESIGN voltage (ACPI _BST on this
// model), so it is rescaled with voltage_now, and its sign is lost: "Charging" only means
// the EC allows charging. With a charger that cannot cover the load the battery drains
// while plugged in, and near that limit it alternates between charging and helping out, so
// |current| says nothing about the net flow. The net flow follows from the charger's USB-PD
// contract (/run/zenbook-duo/charger, written by files/charger-info): the charger delivers
// at most a fixed share of it; whatever the laptop draws beyond that comes from the battery.
//
// Breakdown: RAPL package/core/dram (readable for the wheel group through the module's udev
// rule). Temperatures and fans: hwmon, found by name.

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusVariant>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QQmlEngine>
#include <QQmlExtensionPlugin>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <cmath>
#include <ctime>
#include <qqml.h>

// psys counts this many times the real power on a UX8407AA (measured against the battery).
static constexpr double kPsysScaleDefault = 0.48;
// Share of the USB-PD contract the charger actually draws before the battery has to help:
// the EC keeps its input current limit a little under the contract. Measured with a 40 W
// (20 V 2 A) charger: the battery's net flow is 36.7 W minus what the laptop draws.
static constexpr double kChargerShare = 0.917;
// Within this many watts of that limit the battery alternates between charging and helping
// out: the widget calls it "the charger is fully used".
static constexpr double kLimitBandW = 2.0;
// Learning the psys scale: windows of this many seconds on battery, after the battery's
// current reading (filtered by the EC) has settled following an unplug or a resume. That
// reading trails psys by about 12 s (cross-correlation peak), so psys is delayed to match.
static constexpr double kCalibWindowS = 120;
static constexpr double kCalibSettleS = 60;
static constexpr qint64 kGaugeLagNs = qint64(12) * 1000000000;
// Time estimates follow the battery flow averaged over about a minute.
static constexpr double kEstimateTauS = 60;

static qint64 readInt(const QString &path, bool *ok = nullptr)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        if (ok)
            *ok = false;
        return 0;
    }
    bool good = false;
    const qint64 v = f.readAll().trimmed().toLongLong(&good);
    if (ok)
        *ok = good;
    return v;
}

static QString readStr(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()).trimmed() : QString();
}

// CLOCK_BOOTTIME keeps counting through suspend, like the RAPL energy counters.
static qint64 bootNs()
{
    timespec ts{};
    clock_gettime(CLOCK_BOOTTIME, &ts);
    return qint64(ts.tv_sec) * 1000000000 + ts.tv_nsec;
}

class PowerMonitor : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int interval READ interval WRITE setInterval NOTIFY intervalChanged)
    Q_PROPERTY(bool onAc MEMBER m_onAc NOTIFY updated)
    Q_PROPERTY(QString batteryStatus MEMBER m_batteryStatus NOTIFY updated)
    // discharging (on battery), charging, draining (plugged in, but the battery helps out),
    // limit (plugged in, the charger is fully used and the battery holds), full, idle
    // (plugged in, not charging: charge limit reached)
    Q_PROPERTY(QString batteryState MEMBER m_batteryState NOTIFY updated)
    Q_PROPERTY(int batteryPercent MEMBER m_batteryPercent NOTIFY updated)
    Q_PROPERTY(double batteryWatts MEMBER m_batteryWatts NOTIFY updated) // into the battery: + charging, - discharging
    Q_PROPERTY(double systemWatts MEMBER m_systemWatts NOTIFY updated) // what the laptop itself draws, -1 unknown
    Q_PROPERTY(bool systemFromPsys MEMBER m_systemFromPsys NOTIFY updated)
    Q_PROPERTY(double chargerWatts MEMBER m_chargerWatts NOTIFY updated) // what comes in from the charger, -1 unknown
    Q_PROPERTY(double chargerMaxWatts MEMBER m_chargerMaxWatts NOTIFY updated) // its USB-PD contract, -1 unknown
    Q_PROPERTY(double chargerVolts MEMBER m_chargerVolts NOTIFY updated)
    Q_PROPERTY(double chargerAmps MEMBER m_chargerAmps NOTIFY updated)
    Q_PROPERTY(bool chargerSlow MEMBER m_chargerSlow NOTIFY updated)
    Q_PROPERTY(int minutesToEmpty MEMBER m_minutesToEmpty NOTIFY updated)
    Q_PROPERTY(int minutesToFull MEMBER m_minutesToFull NOTIFY updated)
    Q_PROPERTY(double psysScale MEMBER m_psysScale NOTIFY updated)
    Q_PROPERTY(int psysCalibrations MEMBER m_psysCalibrations NOTIFY updated)
    Q_PROPERTY(bool raplAvailable MEMBER m_raplAvailable NOTIFY updated)
    Q_PROPERTY(double packageWatts MEMBER m_packageWatts NOTIFY updated)
    Q_PROPERTY(double coreWatts MEMBER m_coreWatts NOTIFY updated)
    Q_PROPERTY(double socWatts MEMBER m_socWatts NOTIFY updated)
    Q_PROPERTY(double memoryWatts MEMBER m_memoryWatts NOTIFY updated)
    Q_PROPERTY(double restWatts MEMBER m_restWatts NOTIFY updated)
    Q_PROPERTY(double cpuTemp MEMBER m_cpuTemp NOTIFY updated)
    Q_PROPERTY(double ssdTemp MEMBER m_ssdTemp NOTIFY updated)
    Q_PROPERTY(double wifiTemp MEMBER m_wifiTemp NOTIFY updated)
    Q_PROPERTY(int fanCpu MEMBER m_fanCpu NOTIFY updated)
    Q_PROPERTY(int fanGpu MEMBER m_fanGpu NOTIFY updated)
    Q_PROPERTY(int healthPercent MEMBER m_healthPercent NOTIFY updated)
    Q_PROPERTY(int cycles MEMBER m_cycles NOTIFY updated)
    Q_PROPERTY(int chargeLimit MEMBER m_chargeLimit NOTIFY updated)
    Q_PROPERTY(QString profile MEMBER m_profile NOTIFY updated)

public:
    explicit PowerMonitor(QObject *parent = nullptr)
        : QObject(parent)
        , m_state(QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + QStringLiteral("/zenbook-duo/power-widget.ini"),
                  QSettings::IniFormat)
    {
        m_psysScale = m_state.value(QStringLiteral("psys/scale"), kPsysScaleDefault).toDouble();
        m_psysCalibrations = m_state.value(QStringLiteral("psys/calibrations"), 0).toInt();
        if (!(m_psysScale > 0.25 && m_psysScale < 1.0))
            m_psysScale = kPsysScaleDefault;
        findDevices();
        connect(&m_timer, &QTimer::timeout, this, &PowerMonitor::sample);
        m_timer.setTimerType(Qt::CoarseTimer); // let the kernel batch our wakeups with others
        m_timer.start(m_interval);
        sample();
        QTimer::singleShot(500, this, &PowerMonitor::sample); // the energy counters need two samples for a rate
    }

    int interval() const { return m_interval; }
    void setInterval(int ms)
    {
        ms = qBound(500, ms, 60000);
        if (ms == m_interval)
            return;
        m_interval = ms;
        m_timer.start(ms);
        Q_EMIT intervalChanged();
    }

    Q_INVOKABLE void setProfile(const QString &profile)
    {
        QDBusInterface ppd(QStringLiteral("org.freedesktop.UPower.PowerProfiles"), QStringLiteral("/org/freedesktop/UPower/PowerProfiles"),
                           QStringLiteral("org.freedesktop.DBus.Properties"), QDBusConnection::systemBus());
        ppd.call(QStringLiteral("Set"), QStringLiteral("org.freedesktop.UPower.PowerProfiles"), QStringLiteral("ActiveProfile"),
                 QVariant::fromValue(QDBusVariant(profile)));
        sample();
    }

    Q_INVOKABLE void openPowerSettings()
    {
        QProcess::startDetached(QStringLiteral("systemsettings"), {QStringLiteral("kcm_powerdevilprofilesconfig")});
    }

Q_SIGNALS:
    void updated();
    void intervalChanged();

private:
    void findDevices()
    {
        const QDir hwmon(QStringLiteral("/sys/class/hwmon"));
        for (const QString &h : hwmon.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
            const QString p = hwmon.filePath(h);
            const QString name = readStr(p + QStringLiteral("/name"));
            if (name == QLatin1String("coretemp"))
                m_hwCore = p;
            else if (name == QLatin1String("asus"))
                m_hwAsus = p;
            else if (name == QLatin1String("nvme"))
                m_hwNvme = p;
            else if (name.startsWith(QLatin1String("iwlwifi")))
                m_hwWifi = p;
        }
        // RAPL domains by name: intel-rapl:0 (package-0, with core/uncore/dram below it), intel-rapl:1 (psys)
        const QDir powercap(QStringLiteral("/sys/class/powercap"));
        for (const QString &d : powercap.entryList({QStringLiteral("intel-rapl:*")}, QDir::Dirs | QDir::NoDotAndDotDot)) {
            const QString name = readStr(powercap.filePath(d) + QStringLiteral("/name"));
            if (name == QLatin1String("package-0"))
                m_raplPackage = d;
            else if (name == QLatin1String("core"))
                m_raplCore = d;
            else if (name == QLatin1String("dram"))
                m_raplDram = d;
            else if (name == QLatin1String("psys"))
                m_raplPsys = d;
        }
        const QDir psy(QStringLiteral("/sys/class/power_supply"));
        for (const QString &d : psy.entryList({QStringLiteral("ucsi-source-psy-*")}, QDir::Dirs | QDir::NoDotAndDotDot))
            m_ucsi << psy.filePath(d);
    }

    // Watts from a RAPL energy counter over the time since the previous sample (-1 on the
    // first sample and after a gap such as a suspend).
    double rapl(const QString &domain, qint64 nowNs, bool *ok)
    {
        *ok = false;
        if (domain.isEmpty())
            return -1;
        const QString base = QStringLiteral("/sys/class/powercap/") + domain;
        const qint64 e = readInt(base + QStringLiteral("/energy_uj"), ok);
        if (!*ok)
            return -1;
        Counter &c = m_counters[domain];
        double w = -1;
        if (c.ns > 0 && nowNs > c.ns && !m_gap) {
            qint64 de = e - c.uj;
            if (de < 0) // counter wrapped
                de += readInt(base + QStringLiteral("/max_energy_range_uj"));
            w = double(de) / 1e6 / (double(nowNs - c.ns) / 1e9);
        }
        c = {e, nowNs};
        return w;
    }

    static double smooth(double prev, double now)
    {
        if (now < 0 || std::isnan(now))
            return prev;
        return (prev < 0 || std::isnan(prev)) ? now : prev * 0.5 + now * 0.5;
    }

    // /run/zenbook-duo/charger: port=, watts=, volts=, amps=, slow=
    void readCharger()
    {
        m_chargerMaxWatts = m_chargerVolts = m_chargerAmps = -1;
        bool slow = false;
        QFile f(QStringLiteral("/run/zenbook-duo/charger"));
        if (f.open(QIODevice::ReadOnly)) {
            const auto lines = QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
            for (const QString &line : lines) {
                const qsizetype eq = line.indexOf(QLatin1Char('='));
                if (eq < 0)
                    continue;
                const QString key = line.left(eq), value = line.mid(eq + 1);
                if (key == QLatin1String("watts"))
                    m_chargerMaxWatts = value.toDouble();
                else if (key == QLatin1String("volts"))
                    m_chargerVolts = value.toDouble();
                else if (key == QLatin1String("amps"))
                    m_chargerAmps = value.toDouble();
                else if (key == QLatin1String("slow"))
                    slow = value == QLatin1String("1");
            }
        }
        // without the helper: the kernel still reports the EC's "slow charger" verdict
        for (const QString &p : std::as_const(m_ucsi))
            if (readStr(p + QStringLiteral("/online")) == QLatin1String("1") && readStr(p + QStringLiteral("/charge_type")) == QLatin1String("Trickle"))
                slow = true;
        m_chargerSlow = m_onAc && slow;
    }

    // On battery psys must equal the battery's discharge power: learn the scale over windows
    // of kCalibWindowS seconds and keep a running average across windows and sessions.
    void calibrate(double psysRaw, double batteryW, double dt, qint64 nowNs)
    {
        if (m_onAc || m_batteryStatus != QLatin1String("Discharging") || psysRaw <= 0 || batteryW < 1.0 || m_settleS < kCalibSettleS) {
            m_calib = {};
            m_psysDelay.clear();
            return;
        }
        m_psysDelay.push_back({nowNs, psysRaw * dt});
        while (!m_psysDelay.isEmpty() && m_psysDelay.front().ns <= nowNs - kGaugeLagNs)
            m_calib.psysJ += m_psysDelay.takeFirst().joules;
        if (m_calib.psysJ <= 0) // still filling the delay line
            return;
        m_calib.batteryJ += batteryW * dt;
        m_calib.secs += dt;
        if (m_calib.secs < kCalibWindowS)
            return;
        const double k = m_calib.batteryJ / m_calib.psysJ;
        m_calib = {};
        if (!(k > 0.3 && k < 0.8)) // not this hardware's psys, or a bogus window
            return;
        // the first windows count fully, later ones are averaged in
        const double weight = std::max(0.1, 1.0 / (m_psysCalibrations + 1));
        m_psysScale = m_psysCalibrations ? m_psysScale * (1 - weight) + k * weight : k;
        ++m_psysCalibrations;
        m_state.setValue(QStringLiteral("psys/scale"), m_psysScale);
        m_state.setValue(QStringLiteral("psys/calibrations"), m_psysCalibrations);
        m_state.sync();
    }

    void sample()
    {
        const qint64 nowNs = bootNs();
        const double dt = m_lastNs > 0 ? double(nowNs - m_lastNs) / 1e9 : 0;
        m_gap = m_lastNs > 0 && dt > std::max(10.0, 3.0 * m_interval / 1000.0); // suspended, or the timer stalled
        m_lastNs = nowNs;

        const QString bat = QStringLiteral("/sys/class/power_supply/BAT0/");
        bool okAc = false;
        const bool onAc = readInt(QStringLiteral("/sys/class/power_supply/AC0/online"), &okAc) == 1;
        m_batteryStatus = readStr(bat + QStringLiteral("status"));
        if (!okAc) // no ACPI AC device: trust the battery
            m_onAc = m_batteryStatus != QLatin1String("Discharging");
        else
            m_onAc = onAc;
        m_settleS = (m_onAc != m_wasOnAc || m_gap) ? 0 : m_settleS + dt;
        m_wasOnAc = m_onAc;
        m_batteryPercent = int(readInt(bat + QStringLiteral("capacity")));

        // battery: power_now and energy_* are in "design watts" (current x design voltage)
        const double designV = readInt(bat + QStringLiteral("voltage_min_design")) / 1e6;
        const double nowV = readInt(bat + QStringLiteral("voltage_now")) / 1e6;
        const double toReal = designV > 1 && nowV > 1 ? nowV / designV : 1.0;
        bool okPower = false;
        const double designW = readInt(bat + QStringLiteral("power_now"), &okPower) / 1e6;
        const double batteryW = okPower ? designW * toReal : -1; // |flow| as the EC reports it
        const qint64 eNow = readInt(bat + QStringLiteral("energy_now")), eFull = readInt(bat + QStringLiteral("energy_full")),
                     eDesign = readInt(bat + QStringLiteral("energy_full_design"));
        m_healthPercent = eDesign > 0 ? int(qRound(100.0 * eFull / eDesign)) : -1;
        m_cycles = int(readInt(bat + QStringLiteral("cycle_count")));
        bool okLimit = false;
        m_chargeLimit = int(readInt(bat + QStringLiteral("charge_control_end_threshold"), &okLimit));
        if (!okLimit)
            m_chargeLimit = -1;
        readCharger();

        // charge trend, only for chargers without a known contract
        if (eNow != m_lastEnergy) {
            if (m_lastEnergy > 0 && m_settleS > 0) {
                m_trend = eNow > m_lastEnergy ? 1 : -1;
                m_trendNs = nowNs;
            }
            m_lastEnergy = eNow;
        }
        if (m_settleS == 0 || nowNs - m_trendNs > qint64(180) * 1000000000)
            m_trend = 0;

        // RAPL
        bool ok = false, okc = false, okd = false, okp = false;
        const double pkg = rapl(m_raplPackage, nowNs, &ok);
        const double core = rapl(m_raplCore, nowNs, &okc);
        const double dram = rapl(m_raplDram, nowNs, &okd);
        const double psysRaw = rapl(m_raplPsys, nowNs, &okp);
        m_raplAvailable = ok;
        if (ok) {
            m_packageWatts = smooth(m_packageWatts, pkg);
            m_coreWatts = smooth(m_coreWatts, core);
            m_memoryWatts = smooth(m_memoryWatts, dram);
            m_socWatts = std::max(0.0, m_packageWatts - m_coreWatts);
        }
        if (okp) {
            calibrate(psysRaw, batteryW, dt, nowNs);
            m_psysWatts = smooth(m_psysWatts, psysRaw < 0 ? -1 : psysRaw * m_psysScale);
        } else {
            m_psysWatts = -1;
        }

        // the laptop's own draw
        m_systemFromPsys = okp && m_psysWatts >= 0;
        if (m_systemFromPsys)
            m_systemWatts = m_psysWatts;
        else if (!m_onAc && batteryW >= 0)
            m_systemWatts = batteryW;
        else
            m_systemWatts = -1; // on AC without psys: unknown

        // the battery's net flow (+ into the battery)
        const bool charging = m_batteryStatus == QLatin1String("Charging"), discharging = m_batteryStatus == QLatin1String("Discharging");
        const double limitW = m_onAc && m_chargerMaxWatts > 0 ? m_chargerMaxWatts * kChargerShare : -1;
        const bool contract = limitW > 0 && m_systemWatts >= 0;
        const double headroom = contract ? limitW - m_systemWatts : 0; // what the charger can still give
        double flow = 0;
        if (!m_onAc)
            flow = -(m_systemWatts >= 0 ? m_systemWatts : std::max(0.0, batteryW));
        else if (contract && charging)
            flow = std::min(std::max(0.0, batteryW), headroom); // the battery takes what it accepts, if the charger has it
        else if (contract)
            flow = std::min(0.0, headroom); // full, charge limit reached, or the EC lets it discharge
        else if (charging)
            flow = m_trend < 0 ? -std::max(0.0, batteryW) : std::max(0.0, batteryW);
        else if (discharging)
            flow = -std::max(0.0, batteryW);
        m_batteryWatts = flow;
        if (!m_onAc)
            m_batteryState = QStringLiteral("discharging");
        else if (contract && std::abs(headroom) < kLimitBandW)
            m_batteryState = QStringLiteral("limit");
        else if (flow >= 0.5 || (charging && flow > -0.5))
            m_batteryState = QStringLiteral("charging");
        else if (flow <= -0.5)
            m_batteryState = QStringLiteral("draining");
        else
            m_batteryState = m_batteryStatus == QLatin1String("Full") ? QStringLiteral("full") : QStringLiteral("idle");
        m_chargerWatts = m_onAc && m_systemWatts >= 0 ? std::max(0.0, m_systemWatts + flow) : -1;

        // time estimates in charge terms (energy_* and power_now share the design voltage),
        // from the flow averaged over about a minute
        m_flowAvg = m_settleS == 0 || !m_flowReady ? flow : m_flowAvg + (flow - m_flowAvg) * dt / (kEstimateTauS + dt);
        m_flowReady = !okp || m_psysWatts >= 0; // psys has no rate on the first sample: start over with the next one
        const double flowDesignW = std::abs(m_flowAvg) / toReal;
        m_minutesToEmpty = m_minutesToFull = -1;
        if (m_flowAvg < -0.3)
            m_minutesToEmpty = int(eNow / 1e6 / flowDesignW * 60);
        else if (m_flowAvg > 0.3) {
            const qint64 target = okLimit && m_chargeLimit > 0 && m_chargeLimit < 100 ? eFull * m_chargeLimit / 100 : eFull;
            if (target > eNow)
                m_minutesToFull = int((target - eNow) / 1e6 / flowDesignW * 60);
        }

        m_restWatts = m_raplAvailable && m_systemWatts >= 0 ? std::max(0.0, m_systemWatts - m_packageWatts - std::max(0.0, m_memoryWatts)) : -1;

        m_cpuTemp = m_hwCore.isEmpty() ? -1 : readInt(m_hwCore + QStringLiteral("/temp1_input")) / 1000.0;
        m_ssdTemp = m_hwNvme.isEmpty() ? -1 : readInt(m_hwNvme + QStringLiteral("/temp1_input")) / 1000.0;
        m_wifiTemp = m_hwWifi.isEmpty() ? -1 : readInt(m_hwWifi + QStringLiteral("/temp1_input")) / 1000.0;
        m_fanCpu = m_hwAsus.isEmpty() ? -1 : int(readInt(m_hwAsus + QStringLiteral("/fan1_input")));
        m_fanGpu = m_hwAsus.isEmpty() ? -1 : int(readInt(m_hwAsus + QStringLiteral("/fan2_input")));

        // cheap: one cached D-Bus property read per sample, only while the popup is open
        if (m_interval <= 1500 || m_profile.isEmpty()) {
            QDBusInterface ppd(QStringLiteral("org.freedesktop.UPower.PowerProfiles"), QStringLiteral("/org/freedesktop/UPower/PowerProfiles"),
                               QStringLiteral("org.freedesktop.UPower.PowerProfiles"), QDBusConnection::systemBus());
            const QString p = ppd.property("ActiveProfile").toString();
            if (!p.isEmpty())
                m_profile = p;
        }
        Q_EMIT updated();
    }

    struct Counter {
        qint64 uj = 0;
        qint64 ns = 0;
    };
    struct Calib {
        double psysJ = 0, batteryJ = 0, secs = 0;
    };
    struct Delayed {
        qint64 ns;
        double joules;
    };
    QHash<QString, Counter> m_counters;
    QTimer m_timer;
    QSettings m_state;
    int m_interval = 2000;
    QString m_hwCore, m_hwAsus, m_hwNvme, m_hwWifi;
    QString m_raplPackage, m_raplCore, m_raplDram, m_raplPsys;
    QStringList m_ucsi;
    qint64 m_lastNs = 0, m_lastEnergy = 0, m_trendNs = 0;
    bool m_gap = false, m_wasOnAc = false, m_flowReady = false;
    int m_trend = 0;
    double m_settleS = 0, m_psysWatts = -1, m_flowAvg = 0;
    Calib m_calib;
    QList<Delayed> m_psysDelay;

    bool m_onAc = false, m_systemFromPsys = false, m_chargerSlow = false;
    QString m_batteryStatus, m_batteryState;
    int m_batteryPercent = -1;
    double m_batteryWatts = 0, m_systemWatts = -1, m_chargerWatts = -1;
    double m_chargerMaxWatts = -1, m_chargerVolts = -1, m_chargerAmps = -1;
    int m_minutesToEmpty = -1, m_minutesToFull = -1;
    double m_psysScale = kPsysScaleDefault;
    int m_psysCalibrations = 0;
    bool m_raplAvailable = false;
    double m_packageWatts = -1, m_coreWatts = -1, m_socWatts = -1, m_memoryWatts = -1, m_restWatts = -1;
    double m_cpuTemp = -1, m_ssdTemp = -1, m_wifiTemp = -1;
    int m_fanCpu = -1, m_fanGpu = -1;
    int m_healthPercent = -1, m_cycles = -1, m_chargeLimit = -1;
    QString m_profile;
};

class ZenbookDuoPowerPlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override { qmlRegisterType<PowerMonitor>(uri, 1, 0, "PowerMonitor"); }
};

#include "powermonitor.moc"
