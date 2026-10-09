# This file is part of OpenMediaVault.
#
# @license   https://www.gnu.org/licenses/gpl.html GPL Version 3
# @author    ${GITHUB_USER} <${GITHUB_USER}@users.noreply.github.com>
#
# OpenMediaVault is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.

# Renders /etc/default/rustfs (environment file for the systemd service)
# and the rustfs.service unit from the OMV configuration database.
#
# The service is only deployed when it is enabled AND a data shared folder
# has been selected: without a data directory the environment file would
# not be valid and RustFS must not be started. When either condition is
# not met the service is stopped (idempotently) and the unit file is
# removed, so that applying the configuration never leaves a running
# service behind.
#
# The object data in the shared folder is never touched here.

{% set config = salt['omv_conf.get']('conf.service.rustfs') %}
{% set dataRef = config.dataRef | default('') %}
{% if dataRef | length > 0 %}
{% set datapath = salt['omv_conf.get_sharedfolder_path'](dataRef) %}
{% else %}
{% set datapath = '' %}
{% endif %}
{% set active = (config.enable | to_bool) and (datapath | length > 0) %}

{% if datapath | length > 0 %}

# Always render the environment file, also while the service is disabled, so
# that the generated configuration can be inspected.
render_rustfs_env_file:
  file.managed:
    - name: /etc/default/rustfs
    - source:
      - salt://{{ tpldir }}/files/rustfs.default.j2
    - template: jinja
    - context:
        config: {{ config | json }}
        datapath: "{{ datapath }}"
    - user: root
    - group: root
    - mode: '0600'
    - makedirs: True

{% endif %}

{% if active %}

create_rustfs_log_directory:
  file.directory:
    - name: /var/log/rustfs
    - user: root
    - group: root
    - mode: '0755'
    - makedirs: True

create_rustfs_systemd_unit_file:
  file.managed:
    - name: /etc/systemd/system/rustfs.service
    - source:
      - salt://{{ tpldir }}/files/rustfs.service.j2
    - template: jinja
    - user: root
    - group: root
    - mode: '0644'

rustfs_systemctl_daemon_reload_on:
  module.run:
    - service.systemctl_reload:
    - onchanges:
      - file: create_rustfs_systemd_unit_file

start_rustfs_service:
  service.running:
    - name: rustfs
    - enable: True
    - watch:
      - file: render_rustfs_env_file
      - file: create_rustfs_systemd_unit_file

{% else %}

# Disabled, or the data shared folder is not configured yet: stop the
# service and drop the unit file. Both steps are skipped when the unit
# does not exist, so applying the configuration never fails.
stop_rustfs_service:
  service.dead:
    - name: rustfs
    - enable: False
    - onlyif: test -f /etc/systemd/system/rustfs.service

remove_rustfs_systemd_unit_file:
  file.absent:
    - name: /etc/systemd/system/rustfs.service

rustfs_systemctl_daemon_reload_off:
  module.run:
    - service.systemctl_reload:
    - onchanges:
      - file: remove_rustfs_systemd_unit_file

{% endif %}
