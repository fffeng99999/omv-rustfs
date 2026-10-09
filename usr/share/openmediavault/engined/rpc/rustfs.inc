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

namespace Engined\Rpc;

/**
 * RustFS RPC service.
 *
 * The settings object (conf.service.rustfs) is stored in the OMV
 * configuration database and deployed by the Salt state
 * /srv/salt/omv/deploy/rustfs, which renders /etc/default/rustfs
 * (environment file with the credentials and the data directory) and the
 * rustfs.service systemd unit. The plugin only manages the OMV side
 * integration (configuration, lifecycle, status); RustFS itself is never
 * modified - buckets, users, policies and all other objects are managed
 * in the RustFS console.
 *
 * The service cannot be started before a data shared folder has been
 * selected: the Salt state, the ctl helper and set() all enforce that.
 */
class OMVRpcServiceRustfs extends \OMV\Rpc\ServiceAbstract
{
    const CTL = "/usr/sbin/omv-rustfs-ctl";

    const CONFIG_ID = "conf.service.rustfs";

    /**
     * Version stamp written next to the bundled binary at package build
     * time (the binary is never executed just to read its version).
     */
    const VERSION_FILE = "/usr/share/rustfs/VERSION";

    /**
     * Settings fields allowed to be persisted by set(). The credentials
     * are deliberately not part of this list: they are generated at
     * install time and rotated through regenerateCredentials() only, so
     * an empty form value can never wipe or silently replace them.
     */
    private $settingsFields = [
        "enable", "port", "consolePort", "consoleEnable",
        "dataRef", "logLevel", "extraOptions"
    ];

    public function getName()
    {
        return "Rustfs";
    }

    public function initialize()
    {
        $this->registerMethod("get");
        $this->registerMethod("set");
        $this->registerMethod("start");
        $this->registerMethod("stop");
        $this->registerMethod("restart");
        $this->registerMethod("regenerateCredentials");
        $this->registerMethod("getLog");
        $this->registerMethod("getShowConfig");
    }

    /**
     * Run omv-rustfs-ctl with the given arguments and return the exit
     * status and the trimmed stdout. Throws on failure when
     * $throwOnError is set.
     */
    private function runCtl(array $args, bool $throwOnError = true): array
    {
        $cmd = new \OMV\System\Process(self::CTL, $args);
        $cmd->setRedirect2to1();
        $cmd->setQuiet(true);
        $output = [];
        $exitStatus = 0;
        $cmd->execute($output, $exitStatus);
        if (0 !== $exitStatus && $throwOnError) {
            throw new \OMV\ExecException($cmd, $output, $exitStatus);
        }
        return [$exitStatus, $output];
    }

    private function getSettingsObject($context): array
    {
        return \OMV\Rpc\Rpc::call("Config", "get", [
            "id" => self::CONFIG_ID
        ], $context);
    }

    /**
     * A random hex string; used for the access and secret keys. The
     * upstream default credentials (rustfsadmin) are never used.
     */
    private function generateKey(int $bytes): string
    {
        return bin2hex(random_bytes($bytes));
    }

    /**
     * Settings object enriched with read-only status information for the
     * web interface (service state, bundled version, resolved data path).
     */
    public function get($params, $context)
    {
        $this->validateMethodContext($context, [
            "role" => OMV_ROLE_ADMINISTRATOR
        ]);

        $object = $this->getSettingsObject($context);

        // Fill in defaults for a configuration that was created before a
        // property existed.
        if (!isset($object["logLevel"]) || "" === $object["logLevel"]) {
            $object["logLevel"] = "error";
        }
        if (!isset($object["extraOptions"])) {
            $object["extraOptions"] = "";
        }

        // Service state. The status text is returned as the English msgid;
        // the Workbench form page runs it through the 'translate' filter.
        // The bundled binary is always present, so only two states exist.
        $systemCtl = new \OMV\System\SystemCtl("rustfs");
        $running = $systemCtl->isActive();
        $object["running"] = $running;
        $object["statusText"] = $running ? "Running" : "Stopped";

        $object["version"] = "";
        if (file_exists(self::VERSION_FILE)) {
            $version = @file_get_contents(self::VERSION_FILE);
            $object["version"] = (false === $version) ? "" : trim($version);
        }

        list(, $pathOut) = $this->runCtl(["datapath"], false);
        $object["dataPath"] = trim(implode("\n", $pathOut));

        return $object;
    }

    public function set($params, $context)
    {
        $this->validateMethodContext($context, [
            "role" => OMV_ROLE_ADMINISTRATOR
        ]);

        $data = array_intersect_key($params, array_flip($this->settingsFields));

        // The service must not be enabled before the data shared folder has
        // been selected (the data directory would be missing otherwise).
        $stored = $this->getSettingsObject($context);
        $enable = isset($data["enable"])
            ? (bool)$data["enable"] : (bool)$stored["enable"];
        $dataRef = isset($data["dataRef"])
            ? trim((string)$data["dataRef"]) : trim((string)$stored["dataRef"]);
        if ($enable && "" === $dataRef) {
            throw new \OMV\Exception(
                "Select the data shared folder before enabling RustFS."
            );
        }

        // Repair a configuration whose credentials are missing (e.g. a
        // config node created by hand); never overwrite existing ones.
        if ("" === trim((string)($stored["accessKey"] ?? ""))
            || "" === trim((string)($stored["secretKey"] ?? ""))) {
            $data["accessKey"] = $this->generateKey(12);
            $data["secretKey"] = $this->generateKey(24);
        }

        return \OMV\Rpc\Rpc::call("Config", "set", [
            "id" => self::CONFIG_ID,
            "data" => $data
        ], $context);
    }

    /**
     * Generate a new access/secret key pair and persist it. S3 clients
     * using the previous credentials must be reconfigured afterwards.
     */
    public function regenerateCredentials($params, $context)
    {
        $this->validateMethodContext($context, [
            "role" => OMV_ROLE_ADMINISTRATOR
        ]);
        $accessKey = $this->generateKey(12);
        $secretKey = $this->generateKey(24);
        \OMV\Rpc\Rpc::call("Config", "set", [
            "id" => self::CONFIG_ID,
            "data" => [
                "accessKey" => $accessKey,
                "secretKey" => $secretKey
            ]
        ], $context);
        return [
            "accessKey" => $accessKey,
            "secretKey" => $secretKey
        ];
    }

    public function start($params, $context)
    {
        $this->validateMethodContext($context, [
            "role" => OMV_ROLE_ADMINISTRATOR
        ]);
        $this->runCtl(["start"]);
    }

    public function stop($params, $context)
    {
        $this->validateMethodContext($context, [
            "role" => OMV_ROLE_ADMINISTRATOR
        ]);
        $this->runCtl(["stop"]);
    }

    public function restart($params, $context)
    {
        $this->validateMethodContext($context, [
            "role" => OMV_ROLE_ADMINISTRATOR
        ]);
        $this->runCtl(["restart"]);
    }

    private function execCtlTask($context, string $op): string
    {
        return $this->execBgProc(
            function ($bgStatusFilename, $bgOutputFilename) use ($op) {
                $cmd = new \OMV\System\Process(self::CTL, [$op]);
                $cmd->setRedirect2to1();
                if (0 !== ($exitStatus = $this->exec(
                    $cmd, $output, $bgOutputFilename
                ))) {
                    throw new \OMV\ExecException($cmd, $output, $exitStatus);
                }
                return $output;
            }
        );
    }

    public function getLog($params, $context)
    {
        $this->validateMethodContext($context, [
            "role" => OMV_ROLE_ADMINISTRATOR
        ]);
        return $this->execCtlTask($context, "logs");
    }

    public function getShowConfig($params, $context)
    {
        $this->validateMethodContext($context, [
            "role" => OMV_ROLE_ADMINISTRATOR
        ]);
        return $this->execCtlTask($context, "showconfig");
    }
}
