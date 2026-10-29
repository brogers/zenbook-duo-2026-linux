-- SPDX-License-Identifier: MIT
--
-- ASUS Zenbook Duo 2026 keyboard touchpad on Bluetooth (0b05:1cd8):
-- pointer jump detection on the touchpad's own scan time.
--
-- The touchpad scans every 7.1 ms, the Bluetooth LE link has a connection
-- event every 7.5 ms. About every 130 ms two reports leave in the same
-- connection event and reach the host 0.4-0.8 ms apart. libinput's jump
-- detection divides the distance moved by that arrival interval, sees
-- 10-40 mm per 12 ms and discards the motion: about 1.5 times a second
-- while moving, ~2 mm of finger travel each time.
--
-- Every report carries the scan time (MSC_TIMESTAMP, from the HID Scan Time
-- usage). This plugin turns libinput's jump detection off for the device and
-- runs the same test on the scan time instead: a touch jumped if it moved
-- more than 20 mm in a 12 ms frame, or 7 mm more than in the frame before.
-- A jump is discarded the way libinput does it: the rest of that touch is
-- shifted back by the jump, so the jump itself never reaches the pointer.

libinput:register({ 1 })

local REFERENCE_US = 12000 -- frame interval libinput's thresholds assume
local MAX_INTERVAL_US = 30000 -- longer gaps are not checked (libinput: 2.5 frames)
local ABS_DISTANCE_MM = 20
local REL_DISTANCE_MM = 7

local touchpads = {}

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

local function frame(device, events, timestamp)
	local tp = touchpads[device]
	if not tp then
		return nil
	end

	local msc
	for _, e in ipairs(events) do
		if e.usage == evdev.MSC_TIMESTAMP then
			msc = e.value
		end
	end

	-- Pass 1: follow the slots. The kernel only sends values that changed,
	-- so the last raw position of every slot is kept across touches.
	local first_slot = tp.slot
	local slot = first_slot
	local moved = {}
	for _, e in ipairs(events) do
		local u = e.usage
		if u == evdev.ABS_MT_SLOT then
			slot = e.value
		elseif u == evdev.ABS_MT_TRACKING_ID then
			tp.touches[slot] = e.value >= 0 and { ox = 0, oy = 0, last_mm = 0 } or nil
		elseif u == evdev.ABS_MT_POSITION_X or u == evdev.ABS_MT_POSITION_Y then
			local raw = tp.raw[slot] or {}
			tp.raw[slot] = raw
			if u == evdev.ABS_MT_POSITION_X then
				raw.x = e.value
			else
				raw.y = e.value
			end
			if tp.touches[slot] then
				moved[slot] = true
			end
		end
	end
	tp.slot = slot

	-- Pass 2: the jump test, per touch that moved, on the scan time.
	local shifted = false
	for s in pairs(moved) do
		local t, raw = tp.touches[s], tp.raw[s]
		if raw.x and raw.y then
			if t.px and t.msc and msc and msc > t.msc and msc - t.msc <= MAX_INTERVAL_US then
				local dx, dy = raw.x - t.px, raw.y - t.py
				local mm = math.sqrt((dx / tp.res_x) ^ 2 + (dy / tp.res_y) ^ 2)
				local per_frame = mm * REFERENCE_US / (msc - t.msc)
				if per_frame > ABS_DISTANCE_MM or per_frame - t.last_mm > REL_DISTANCE_MM then
					t.ox = t.ox + dx
					t.oy = t.oy + dy
					libinput:log_debug(string.format("touch jump of %.1f mm discarded", mm))
				end
				t.last_mm = per_frame
			end
			t.px, t.py = raw.x, raw.y
			t.msc = msc or t.msc
		end
	end
	for _, t in pairs(tp.touches) do
		if t.ox ~= 0 or t.oy ~= 0 then
			shifted = true
		end
	end
	if not shifted then
		return nil
	end

	-- Pass 3: report shifted positions for touches that jumped earlier.
	slot = first_slot
	for _, e in ipairs(events) do
		local u = e.usage
		if u == evdev.ABS_MT_SLOT then
			slot = e.value
		elseif u == evdev.ABS_MT_POSITION_X or u == evdev.ABS_MT_POSITION_Y then
			local t = tp.touches[slot]
			if t then
				if u == evdev.ABS_MT_POSITION_X then
					e.value = clamp(e.value - t.ox, tp.min_x, tp.max_x)
				else
					e.value = clamp(e.value - t.oy, tp.min_y, tp.max_y)
				end
			end
		end
	end
	return events
end

libinput:connect("new-evdev-device", function(device)
	local info = device:info()
	if info.vid ~= 0x0b05 or info.pid ~= 0x1cd8 or info.bustype ~= evdev.BUS_BLUETOOTH then
		return
	end
	local abs = device:absinfos()
	local ax, ay = abs[evdev.ABS_MT_POSITION_X], abs[evdev.ABS_MT_POSITION_Y]
	if not (ax and ay) or ax.resolution <= 0 or ay.resolution <= 0 then
		return
	end

	-- libinput drops MSC_TIMESTAMP unless a quirk asks to watch it; it
	-- does so before plugins see the device, so ask for it back here.
	device:enable_evdev_usage(evdev.MSC_TIMESTAMP)
	device:disable_feature("touchpad-jump-detection")
	touchpads[device] = {
		slot = 0,
		touches = {},
		raw = {},
		res_x = ax.resolution,
		res_y = ay.resolution,
		min_x = ax.minimum,
		max_x = ax.maximum,
		min_y = ay.minimum,
		max_y = ay.maximum,
	}
	device:connect("evdev-frame", frame)
	device:connect("device-removed", function(d)
		touchpads[d] = nil
	end)
	libinput:log_info(device:name() .. ": jump detection on the touchpad scan time")
end)
