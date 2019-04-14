# Copyright 2019 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

inherit eutils toolchain-funcs linux-info

DESCRIPTION="x86 power tools bundled with kernel sources"
HOMEPAGE="https://kernel.org/"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="-* ~amd64 ~x86"
IUSE=""
RDEPEND="!sys-apps/linux-misc-apps"

my_file_uri() {
	printf 'https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/%s?h=v%s' \
		"${1:?}" \
		"${PV}"
}

my_pfile_uri() { my_file_uri "tools/power/x86/${1:?}"; }

SRC_URI="
	$(my_file_uri arch/x86/include/asm/intel-family.h) -> ${PF}_intel-family.h
	$(my_file_uri arch/x86/include/asm/msr-index.h) -> ${PF}_msr-index.h

	$(my_pfile_uri turbostat/turbostat.c) -> ${PF}_turbostat.c
	$(my_pfile_uri turbostat/turbostat.8) -> ${PF}_turbostat.8

	$(my_pfile_uri x86_energy_perf_policy/x86_energy_perf_policy.c) -> ${PF}_x86_energy_perf_policy.c
	$(my_pfile_uri x86_energy_perf_policy/x86_energy_perf_policy.8) -> ${PF}_x86_energy_perf_policy.8
"

S="${WORKDIR}"

CONFIG_CHECK="~X86_MSR"

PATCHES=( "${FILESDIR}/turbostat-include-limits.patch" )

MY_PROGS="x86_energy_perf_policy turbostat"

src_unpack() {
	local iter

	for iter in intel-family msr-index; do
		cp -- "${DISTDIR}/${PF}_${iter}.h" "${S}/${iter}.h" || die
	done

	for iter in ${MY_PROGS:?}; do
		cp -- "${DISTDIR}/${PF}_${iter}.c" "${S}/${iter}.c" || die
		cp -- "${DISTDIR}/${PF}_${iter}.8" "${S}/${iter}.8" || die
	done
}

src_compile() {
	local prog

	for prog in ${MY_PROGS:?}; do
		$(tc-getCC) ${CFLAGS} ${CPPFLAGS} ${LDFLAGS} \
			-DMSRHEADER='"msr-index.h"' \
			-DINTEL_FAMILY_HEADER='"intel-family.h"' \
			-o "${prog}" "${prog}.c" || die "Failed to compile ${prog}"
	done
}

src_install() {
	local prog

	for prog in ${MY_PROGS:?}; do
		dosbin "${prog}"
		doman "${prog}.8"
	done
}
