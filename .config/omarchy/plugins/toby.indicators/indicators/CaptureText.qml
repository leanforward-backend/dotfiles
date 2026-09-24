import QtQuick
import qs.Ui

BarIndicator {
  id: root

  activeText: "󰴑"
  inactiveText: "󰴑"
  activeTooltipText: "Copy Text from Screen"
  inactiveTooltipText: "Copy Text from Screen"

  onPressed: function() {
    if (root.bar) {
      root.bar.run("omarchy-capture-text")
    }
  }
}
