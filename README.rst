.. _TLP:
   http://linrunner.de/en/tlp/tlp.html

.. _TLP git repo:
   https://github.com/linrunner/TLP

.. _tlp-gentoo-additions:
   https://github.com/dywisor/tlp-gentoo-additions

.. _tlp-portage:
   git://github.com/dywisor/tlp-portage.git

.. _Layman - Gentoo Wiki:
   http://wiki.gentoo.org/wiki/Layman

.. _tpacpi-bat:
   https://github.com/teleshoes/tpacpi-bat

.. _upstream documentation:
   http://www.linrunner.de/en/tlp/docs/tlp-configuration.html

.. _Sabayon Package Repo:
   http://yugoloth.de/dywi/tlp-sabayon/

=============
 tlp-portage
=============

Overlay for installing `TLP`_ on Gentoo/Funtoo/... systems.

Binary packages for Sabayon are available, too,
see the `Sabayon Package Repo`_ for details.


Setup Instructions
==================

The following commands (``$ <command...>``) should be run as root.
It is assumed that your package manager is ``sys-apps/portage``.


#. Install layman

   #. Enable the git USE flag for layman::

      $ mkdir /etc/portage/package.use
      $ echo "app-portage/layman git" >> /etc/portage/package.use/layman

   #. Install layman::

      $ emerge -a --noreplace ">=app-portage/layman-2"

   See also `Layman - Gentoo Wiki`_.

#. Make sure that ``/etc/portage/make.conf`` has the following line::

      source /var/lib/layman/make.conf

   If you've just installed layman, simply run::

      $ echo "source /var/lib/layman/make.conf" >> /etc/portage/make.conf

#. Add the *tlp-portage* overlay with layman::

      $ wget "https://raw.github.com/dywisor/tlp-portage/maint/layman.xml" -O /etc/layman/overlays/tlp.xml
      $ layman -f -a tlp

#. **stable arch** only (amd64, x86): unmask *TLP*:

   .. code::

      $ mkdir /etc/portage/package.accept_keywords
      $ echo "app-laptop/tlp" > /etc/portage/package.accept_keywords/tlp

   unmask sys-power/linux-x86-power-tools or sys-apps/linux-misc-apps:

   .. code::

      $ echo "sys-power/linux-x86-power-tools" >> /etc/portage/package.accept_keywords/tlp

#. *(optional)* install/build kernel modules

   This is required for ThinkPad advanced battery functions.

   * Thinkpads up to the Sandy Bridge generation (T420, X220 et al.)::

      $ emerge -a app-laptop/tp_smapi

   * Thinkpads beginning with the Sandy Bridge Generation (T420, X220 et al.)::

      $ emerge -a sys-power/acpi_call

#. *(optional)* choose USE flags, for example::

      $ echo "app-laptop/tlp tlp_suggests" > /etc/portage/package.use/tlp

   See `USE flags`_ below for a full listing.

#. Install *TLP*::

      $ emerge -a app-laptop/tlp

#. Edit *TLP's* configuration file **/etc/tlp.conf**

   In contrast to other distributions, the config file is not in */etc/default*
   and **you have to enable TLP explicitly** by setting ``TLP_ENABLE=1``.

   See the `upstream documentation`_ for details.


#. Enable the *TLP* service

   **OpenRC** (most Gentoo users)::

      $ rc-update add tlp default

   **systemd**::

      $ systemctl enable tlp.service
      $ systemctl enable tlp-sleep.service

   ``systemd-rfkill`` should be masked as it conflicts with
   ``RESTORE_DEVICE_STATE_ON_STARTUP``/``DEVICES_TO_{EN,DIS}ABLE_ON_STARTUP``::

      $ systemctl mask systemd-rfkill.socket systemd-rfkill.service

   Users of systemd prior to v227 need to mask ``systemd-rfkill@`` instead::

      $ systemctl mask systemd-rfkill@.service

#. Enable or restart/reload the *acpid* service

#. Start **TLP**::

      $ tlp start

#. You might want to run ``tlp-stat`` to see if everything is OK so far



-----------
 USE flags
-----------

.. table:: USE flags accepted by app-laptop/tlp

   +--------------+--------------+---------+--------------------------------------+
   | flag         | recommended  | default | description                          |
   +==============+==============+=========+======================================+
   | tlp_suggests | yes          | no      | install all optional dependencies    |
   +--------------+--------------+---------+--------------------------------------+
   | rdw          | \-           | no      | install *TLP's* radio device wizard  |
   +--------------+--------------+---------+--------------------------------------+
   | pm-utils     | yes (OpenRC) | yes     | depend on ``sys-power/pm-utils``     |
   |              |              |         | (can only be deselected when         |
   |              | \- (systemd) |         | using systemd)                       |
   +--------------+--------------+---------+--------------------------------------+
   | deprecated   | \-           | no      | install *thinkpad-radiosw*, which    |
   |              |              |         | works with older kernel versions     |
   |              |              |         | only.                                |
   |              |              |         |                                      |
   |              |              |         | removed in 0.9  (*future* release)   |
   +--------------+--------------+---------+--------------------------------------+
   | bluetooth    | \-           | no      | install optional bluetooth           |
   |              |              |         | dependencies (bluez)                 |
   +--------------+--------------+---------+--------------------------------------+
   | tpacpi-\     | **yes**      | yes     | use the bundled version of           |
   | bundled      |              |         | `tpacpi-bat`_                        |
   |              |              |         |                                      |
   |              |              |         | Deselecting this flag                |
   |              |              |         | **disqualifies you from getting \    |
   |              |              |         | support upstream**                   |
   +--------------+--------------+---------+--------------------------------------+
   | laptop-\     | **no**       | no      | Allow parallel installation of       |
   | mode-\       |              |         | ``app-laptop/tlp`` and               |
   | tools        |              |         | ``app-laptop/laptop-mode-tools``.    |
   |              |              |         | Having both active at the same time  |
   |              |              |         | is not supported at all.             |
   +--------------+--------------+---------+--------------------------------------+


--------------------
 Random notes / FAQ
--------------------


Kernel config considerations
----------------------------

The following kernel options should be set to *y*:

* CONFIG_PM
* CONFIG_PM_RUNTIME (Linux < 3.19 only)
* CONFIG_DMIID
* CONFIG_POWER_SUPPLY
* CONFIG_ACPI_AC
* CONFIG_SENSORS_CORETEMP
* CONFIG_X86_MSR

* CONFIG_ACPI_PROC_EVENT

  removed in Linux >= 3.12 (and deprecated before),
  required for ``thinkpad-radiosw``
  (``DEVICES_TO_ENABLE_ON_RADIOSW`` in the config file)

  * enable if you have a ThinkPad and an older kernel (e.g. 3.10)
  * don't care about it on newer kernel versions, but lose ``thinkpad-radiosw``

  Future versions of TLP (>= 0.9) will no longer support this feature.
