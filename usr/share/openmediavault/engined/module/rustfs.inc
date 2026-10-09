<?php

/**
 * This file is part of OpenMediaVault.
 *
 * @license   https://www.gnu.org/licenses/gpl.html GPL Version 3
 * @author    ${GITHUB_USER} <${GITHUB_USER}@users.noreply.github.com>
 *
 * OpenMediaVault is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * any later version.
 *
 * OpenMediaVault is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */

namespace Engined\Module;

/**
 * RustFS engine module.
 *
 * Marks the module dirty whenever the settings or the referenced shared
 * folder change so that 'Apply changes' re-runs the Salt state
 * (/etc/default/rustfs and the rustfs.service unit), and reports the
 * service status to the global Services monitoring (dashboard).
 */
class Rustfs extends \OMV\Engine\Module\ServiceAbstract
	implements \OMV\Engine\Notify\IListener, \OMV\Engine\Module\IServiceStatus
{
	public function getName()
	{
		return "rustfs";
	}

	public function getStatus()
	{
		$db = \OMV\Config\Database::getInstance();
		$object = $db->get("conf.service.rustfs");
		$systemCtl = new \OMV\System\SystemCtl("rustfs");
		return [
			"name" => $this->getName(),
			"title" => gettext("RustFS"),
			"enabled" => $object->get("enable"),
			"running" => $systemCtl->isActive()
		];
	}

	public function bindListeners(\OMV\Engine\Notify\Dispatcher $dispatcher)
	{
		$dispatcher->addListener(
			OMV_NOTIFY_MODIFY,
			"org.openmediavault.conf.service.rustfs",
			[$this, "setDirty"]
		);
		// The data directory is a shared folder reference, so a modified
		// shared folder must mark the service dirty when it is the one
		// that is referenced here.
		$dispatcher->addListener(
			OMV_NOTIFY_MODIFY,
			"org.openmediavault.conf.system.sharedfolder",
			[$this, "onSharedFolder"]
		);
	}

	public function onSharedFolder($object)
	{
		$db = \OMV\Config\Database::getInstance();
		if ($db->exists("conf.service.rustfs", [
			"operator" => "stringEquals",
			"arg0" => "dataRef",
			"arg1" => $object["uuid"]
		])) {
			$this->setDirty();
		}
	}
}
