# Copyright 1999-2011 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

EAPI=4

inherit tlp
# inherited DEPEND DESCRIPTION HOMEPAGE IUSE KEYWORDS LICENSE RDEPEND RESTRICT SLOT SRC_URI

src_configure() {
	tlp_configure
}

src_compile() {
	tlp_compile
}

pkg_postinst() {
	tlp_postinst
}

pkg_preinst() {
	tlp_preinst
}

pkg_postrm() {
	tlp_postrm
}

src_install() {
	tlp_install
}
