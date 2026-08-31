import QtQuick
import qs.Ui

BarIndicator {
  id: root

  activeText: ""
  inactiveText: ""
  activeTooltipText: "Screenshot"
  inactiveTooltipText: "Screenshot"

  onPressed: function() {
    if (root.bar) {
      root.bar.run("omarchy-capture-screenshot")
    }
  }
}
