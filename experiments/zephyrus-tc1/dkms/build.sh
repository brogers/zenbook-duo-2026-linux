#!/bin/bash
# build.sh KERNELVER KERNEL_SOURCE_DIR
# build.sh --fetch     (pacman hook: usr/lib/modules/<kernelver>/build/include/ lines on stdin)
# Build xe.ko for KERNELVER from that kernel's own sources plus patches/.
#
# The headers package has no driver sources, so fetch drivers/gpu/drm/{xe,i915}
# from the tree the kernel was built from (sparse, blob-filtered clone; cached
# under /var/cache/zephyrus-duo/xe-src):
#   *-cachyos*  github.com/CachyOS/linux     tag cachyos-<ver>-<n>, n = the package
#               release (7.3.0-2-cachyos: cachyos-7.3.0-2), else the newest n below it
#   *-archN-*   github.com/archlinux/linux   tag v<ver>-archN
#   otherwise   kernel.org stable            tag v<ver>
#
# pacman 7.1 runs hooks, the DKMS one included, without network access. The pacman
# hook 65-zephyrus-duo-xe-sources.hook may use the network: it runs --fetch for the
# new kernels just before DKMS, so the build finds their sources in the cache.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cache=/var/cache/zephyrus-duo/xe-src
export GIT_TERMINAL_PROMPT=0
# never hang a kernel update on a slow or dead network; GitHub can take a minute
# before it sends the first byte for this repository
git_net() { timeout "$1" git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=90 "${@:2}"; }

# pick_tag PREFIX REL: of the tag names on stdin, PREFIX-REL if there is one, else the
# newest PREFIX-n below it (a rebuild without new sources), else the newest
pick_tag() {
	grep -E "^${1//./\\.}-[0-9]+$" | sort -V | awk -F- -v rel="${2:-0}" '
		{ last = $0 }
		$NF == rel { exact = $0 }
		$NF <= rel { below = $0 }
		END { print (exact != "") ? exact : (below != "") ? below : last }'
}

# fetch TAG: TAG's sources into src/, from the cache or a sparse clone
fetch() {
	rm -rf src
	if [[ -d $cache/$1/drivers/gpu/drm/xe ]]; then
		cp -a "$cache/$1" src
		return
	fi
	git_net 600 -c advice.detachedHead=false clone -q --depth 1 --filter=blob:none --no-checkout --branch "$1" "$repo" src &&
		git -C src sparse-checkout set --no-cone /drivers/gpu/drm/xe/ /drivers/gpu/drm/i915/ &&
		git_net 600 -C src checkout -q || { rm -rf src; return 1; }
	rm -rf src/.git
	mkdir -p "$cache" && rm -rf "${cache:?}/$1" && cp -a src "$cache/$1"
	# keep the three most recent source trees
	ls -1dt "$cache"/*/ 2>/dev/null | tail -n +4 | xargs -r rm -rf
}

# sources KERNELVER: that kernel's sources into src/; sets repo and tag
sources() {
	local kver="$1" series sub rc rel up cachy want
	[[ $kver =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-rc[0-9]+)?(-([0-9]+))? ]] || { echo "unknown kernel version $kver" >&2; return 1; }
	series="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}" sub="${BASH_REMATCH[3]}" rc="${BASH_REMATCH[4]}" rel="${BASH_REMATCH[6]}"
	# kernel.org and Arch tag x.y.0 as x.y; CachyOS keeps the .0 on releases
	# (cachyos-7.3.0-2) but not on release candidates (cachyos-7.3-rc6-1)
	up="$series"
	[[ $sub != 0 ]] && up+=".$sub"
	up+="$rc"
	cachy="$series"
	[[ -z $rc ]] && cachy+=".$sub"
	cachy+="$rc"

	case "$kver" in
	*cachyos*)
		repo=https://github.com/CachyOS/linux.git
		want="cachyos-$cachy-$rel"
		tag="$want"
		# The tag of this package release usually exists. Otherwise list the tags (slow:
		# the repository has tens of thousands), or offline take a cached tree of this version.
		if [[ -z $rel ]] || ! fetch "$tag"; then
			tag="$(git_net 120 ls-remote --tags --refs "$repo" "cachyos-$cachy-*" 2>/dev/null | sed 's|.*refs/tags/||' | pick_tag "cachyos-$cachy" "$rel" || true)"
			[[ -n $tag ]] || tag="$(ls -1 "$cache" 2>/dev/null | pick_tag "cachyos-$cachy" "$rel" || true)"
			[[ -n $tag ]] || { echo "no source tag found for $kver in $repo" >&2; return 1; }
			fetch "$tag" || { echo "cannot fetch $repo $tag" >&2; return 1; }
			[[ -z $rel || $tag == "$want" ]] || echo "warning: no $want, using the sources of $tag" >&2
		fi
		;;
	*-arch[0-9]*)
		repo=https://github.com/archlinux/linux.git
		[[ $kver =~ -(arch[0-9]+) ]]
		tag="v$up-${BASH_REMATCH[1]}"
		fetch "$tag" || { echo "cannot fetch $repo $tag" >&2; return 1; }
		;;
	*)
		repo=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
		tag="v$up"
		fetch "$tag" || { echo "cannot fetch $repo $tag" >&2; return 1; }
		;;
	esac
}

if [[ ${1:-} == --fetch ]]; then
	excl="$(sed -n 's/^BUILD_EXCLUSIVE_KERNEL="\(.*\)"$/\1/p' "$here/dkms.conf")"
	work="$(mktemp -d)"
	trap 'rm -rf "$work"' EXIT
	cd "$work"
	while read -r path; do
		kver="${path#usr/lib/modules/}"
		kver="${kver%%/*}"
		[[ -z $excl || $kver =~ $excl ]] || continue
		if sources "$kver"; then
			echo "zephyrus-duo: xe sources for $kver: $tag"
		fi
	done
	exit 0
fi

kver="$1" kdir="$2"
sources "$kver" || exit 1
echo "xe sources: $repo $tag"

for p in "$here"/patches/*.patch; do
	patch -d src -p1 --forward --quiet <"$p"
done

# Out-of-tree build: xe compiles the display code from ../i915/display, and the
# trace headers point TRACE_INCLUDE_PATH at the in-tree location.
cd src/drivers/gpu/drm
sed -i 's|\$(srctree)/drivers/gpu/drm/i915/|$(src)/../i915/|g' xe/Makefile
sed -i 's|^#define TRACE_INCLUDE_PATH \.\./\.\./drivers/gpu/drm/.*|#define TRACE_INCLUDE_PATH .|' \
	xe/xe_trace*.h i915/display/intel_display_trace.h

llvm=()
grep -q '^CONFIG_CC_IS_CLANG=y' "$kdir/.config" && llvm=(LLVM=1)
make -C "$kdir" M="$PWD/xe" "${llvm[@]}" -j"$(nproc)" modules
