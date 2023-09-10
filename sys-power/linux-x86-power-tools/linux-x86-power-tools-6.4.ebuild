# Copyright 1999-2023 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

inherit autotools flag-o-matic linux-info toolchain-funcs

DESCRIPTION="x86 power tools bundled with kernel sources"
HOMEPAGE="https://kernel.org/"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="-* ~amd64 ~x86"
IUSE=""

MY_PV="${PV/_/-}"
MY_PV="${MY_PV/-pre/-git}"

LINUX_V=$(ver_cut 1-2)

_get_version_component_count() {
	local cnt=( $(ver_rs 1- ' ') )
	echo ${#cnt[@]} || die
}

if [ ${PV/_rc} != ${PV} ]; then
	LINUX_VER=$(ver_cut 1-2).$(($(ver_cut 3)-1))
	PATCH_VERSION=$(ver_cut 1-3)
	LINUX_PATCH=patch-${PV//_/-}.xz
	SRC_URI="https://www.kernel.org/pub/linux/kernel/v3.x/testing/${LINUX_PATCH}
		https://www.kernel.org/pub/linux/kernel/v3.x/testing/v${PATCH_VERSION}/${LINUX_PATCH}"
elif [ $(_get_version_component_count) == 4 ]; then
	# stable-release series
	LINUX_VER=$(ver_cut 1-3)
	LINUX_PATCH=patch-${PV}.xz
	SRC_URI="https://www.kernel.org/pub/linux/kernel/v3.x/${LINUX_PATCH}"
else
	LINUX_VER=${PV}
fi

LINUX_SOURCES=linux-${LINUX_VER}.tar.xz
SRC_URI="${SRC_URI} https://www.kernel.org/pub/linux/kernel/v3.x/${LINUX_SOURCES}"

DEPEND=">=sys-kernel/linux-headers-${LINUX_V}"
RDEPEND="!sys-apps/linux-misc-apps"
CONFIG_CHECK="~X86_MSR"

S="${WORKDIR}/linux-${LINUX_VER}"

# These have a broken make install, no DESTDIR
TARGET_MAKE_SIMPLE=(
	tools/power/x86/turbostat:turbostat
	tools/power/x86/x86_energy_perf_policy:x86_energy_perf_policy
	tools/thermal/tmon:tmon
)

src_unpack() {
	unpack ${LINUX_SOURCES}

	MY_A=
	for _AFILE in ${A}; do
		[[ ${_AFILE} == ${LINUX_SOURCES} ]] && continue
		[[ ${_AFILE} == ${LINUX_PATCH} ]] && continue
		MY_A="${MY_A} ${_AFILE}"
	done
	[[ -n ${MY_A} ]] && unpack ${MY_A}
}

src_prepare() {
	if [[ -n ${LINUX_PATCH} ]]; then
		eapply "${DISTDIR}"/${LINUX_PATCH}
	fi

	eapply_user
}

src_configure() {
	append-cflags -fcommon
}

src_compile() {
	# NOTE: hardcoded arch
	local karch=x86

	# Now we can start building
	append-cflags -I./tools/lib

	for t in ${TARGET_MAKE_SIMPLE[@]} ; do
		dir=${t/:*} target_binfile=${t#*:}
		target=${target_binfile/:*} binfile=${target_binfile/*:}
		[ -z "${binfile}" ] && binfile=$target
		einfo "Building $dir => $binfile (via emake $target)"
		emake -C $dir ARCH=${karch} $target
	done
}

src_install() {
	into /usr
	for t in ${TARGET_MAKE_SIMPLE[@]} ; do
		dir=${t/:*} target_binfile=${t#*:}
		target=${target_binfile/:*} binfile=${target_binfile/*:}
		[ -z "${binfile}" ] && binfile=$target
		einfo "Installing $dir => $binfile"
		dosbin ${dir}/${binfile}
		[ ! -r ${dir}/${binfile}.8 ] || doman ${dir}/${binfile}.8
	done
}
