# Copyright 1999-2012 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

EAPI=4

_GITREF="43ac26a8a3bb3d3d472555c4cb2845bd76f0a188"

DESCRIPTION="Exposes battery control through ACPI as an alternative to app-laptop/tp_smapi"
HOMEPAGE="https://github.com/teleshoes/tpbattstat-applet"
SRC_URI="https://raw.github.com/teleshoes/tpbattstat-applet/master/tpacpi-bat"
RESTRICT="mirror"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="~x86 ~amd64"

inherit eutils

IUSE="+acpi_call"
DEPEND="${DEPEND:-}"
RDEPEND="${RDEPEND:-}
	dev-lang/perl
	acpi_call? ( sys-power/acpi_call )
"

S="${WORKDIR}"

src_unpack() {
	local x=
	for x in ${A}; do
		cp -L "${DISTDIR}/${x}" "${S}/${x}" || die "cp $x"
	done
}

src_prepare() {
	epatch_user
}

src_install() {
	dosbin ${PN}
}

pkg_postinst() {
	if ! use acpi_call; then
		ewarn "You've deselected the acpi_call USE flag. Make to sure to have an acpi_call module running!"
	fi
}
