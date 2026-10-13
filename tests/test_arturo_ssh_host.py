import json
import pathlib
import unittest

PLUGIN = pathlib.Path(__file__).resolve().parents[1]


class PluginContractTests(unittest.TestCase):
    def test_manifest_declares_ssh_host_plugin(self):
        manifest = json.loads((PLUGIN / "manifest.json").read_text())
        self.assertEqual(manifest["id"], "arturo.ssh-host")
        # Single bar-widget entry like omarchy.tailscale: a separate "panel"
        # kind is loaded apart from the bar and can't anchor to the icon.
        self.assertEqual(manifest["kinds"], ["bar-widget"])
        self.assertEqual(manifest["entryPoints"], {"barWidget": "Panel.qml"})

    def test_panel_qml_has_process_and_timer(self):
        qml = (PLUGIN / "Panel.qml").read_text()
        self.assertIn("Process", qml)
        self.assertIn("Timer", qml)

    def test_panel_floats_next_to_bar_icon(self):
        qml = (PLUGIN / "Panel.qml").read_text()
        self.assertIn("BarIconButton", qml)
        self.assertIn("anchorItem: button", qml)
        self.assertNotIn("centerOnBar", qml)
        self.assertNotIn("AnchorBridge", qml)

    def test_panel_qml_has_ssh_info(self):
        qml = (PLUGIN / "Panel.qml").read_text()
        self.assertIn("host", qml.lower())

    def test_panel_ipc_is_not_disabled(self):
        # ipcTarget alone is inert if manageIpc is set to false with no
        # replacement IpcHandler declared anywhere - that combination made
        # omarchy-shell arturo.ssh-host open/close/toggle silently do
        # nothing. Guard against reintroducing that.
        qml = (PLUGIN / "Panel.qml").read_text()
        self.assertIn('ipcTarget: "arturo.ssh-host"', qml)
        self.assertNotIn("manageIpc: false", qml)

    def test_single_periodic_poller(self):
        # Panel.qml owns both the bar icon and the popup, so exactly one
        # periodic refreshIntervalSec timer should spawn ssh_hosts.py.
        qml = (PLUGIN / "Panel.qml").read_text()
        self.assertEqual(qml.count("refreshIntervalSec"), 1)
        self.assertFalse((PLUGIN / "Widget.qml").exists())

    def test_ssh_hosts_py_parses_config(self):
        ssh_path = PLUGIN / "ssh_hosts.py"
        self.assertTrue(ssh_path.exists(), "ssh_hosts.py must exist")
        content = ssh_path.read_text()
        self.assertIn("config_path = Path.home()", content)
        self.assertIn("host_blocks", content)
        self.assertIn("localforward", content)

    def test_ssh_hosts_py_ssh_check(self):
        ssh_path = PLUGIN / "ssh_hosts.py"
        content = ssh_path.read_text()
        self.assertIn("subprocess.run", content)
        self.assertIn("BatchMode=yes", content)
        self.assertIn("ConnectTimeout=1", content)