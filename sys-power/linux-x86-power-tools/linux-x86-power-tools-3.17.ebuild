# Copyright 1999-2014 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

EAPI=5

inherit versionator eutils toolchain-funcs linux-info

DESCRIPTION="x86 power tools bundled with kernel sources"
HOMEPAGE="http://kernel.org/"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="-* ~amd64 ~x86"
IUSE=""
RDEPEND="!sys-apps/linux-misc-apps"

MY_PV="${PV/_/-}"
MY_PV="${MY_PV/-pre/-git}"

LINUX_V=$(get_version_component_range 1-2)

if [[ "${PV/_rc}" != "${PV}" ]]; then
	LINUX_VER=$(get_version_component_range 1-2).$(($(get_version_component_range 3)-1))
	PATCH_VERSION=$(get_version_component_range 1-3)
	LINUX_PATCH="patch-${PV//_/-}.xz"
	SRC_URI="mirror://kernel/linux/kernel/v${LINUX_V}/testing/${LINUX_PATCH}
		mirror://kernel/linux/kernel/v${LINUX_V}/testing/v${PATCH_VERSION}/${LINUX_PATCH}"
elif [ $(get_version_component_count) == 4 ]; then
	# stable-release series
	LINUX_VER=$(get_version_component_range 1-3)
	LINUX_PATCH="patch-${PV}.xz"
	SRC_URI="mirror://kernel/linux/kernel/v${LINUX_V}/${LINUX_PATCH}"
else
	LINUX_VER="${PV}"
fi

LINUX_SOURCES=linux-${LINUX_VER}.tar.xz
SRC_URI="${SRC_URI} mirror://kernel/linux/kernel/v${LINUX_V}/${LINUX_SOURCES}"

S="${WORKDIR}/linux-${LINUX_VER}"

MY_LINUX_X86_PROGS="x86_energy_perf_policy turbostat"

pkg_pretend() {
	CONFIG_CHECK="~X86_MSR"

	check_extra_config
}

pkg_setup() { :; }

src_unpack() {
	unpack "${LINUX_SOURCES}"

	MY_A=
	for _AFILE in ${A}; do
		case "${_AFILE}" in
			"${LINUX_SOURCES}"|"${LINUX_PATCH}") : ;;
			*)
				MY_A="${MY_A} ${_AFILE}"
			;;
		esac
	done
	[[ -z "${MY_A}" ]] || unpack ${MY_A}
}

src_prepare() {
	[[ -z "${LINUX_PATCH}" ]] || epatch "${DISTDIR}/${LINUX_PATCH}"
}

src_compile() {
	local prog

	for prog in ${MY_LINUX_X86_PROGS:?}; do
		emake -C "./tools/power/x86/${prog}/" \
			BUILD_OUTPUT=. ARCH=$(tc-arch-kernel) "${prog}"
	done
}

src_install() {
	local prog manp

	for prog in ${MY_LINUX_X86_PROGS:?}; do
		dosbin "./tools/power/x86/${prog}/${prog}"

		for manp in "./tools/power/x86/${prog}/${prog}."[1-9]*; do
			[[ ! -f "${manp}" ]] || doman "${manp}"
		done
	done
}
