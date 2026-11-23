import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Commons.Color.foreground
  property color badgeColor: Commons.Color.urgent
  property bool syncing: false
  property bool crossed: false
  property bool warning: false
  property bool paused: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real cx: width / 2
  readonly property real cy: height / 2
  readonly property real ringRadius: iconSize * 0.34
  readonly property real strokeWidth: Math.max(1.5, iconSize * 0.125)
  readonly property real arrowsOpacity: (root.paused && !root.warning && !root.crossed)
    ? 0.48
    : (root.crossed ? 0.6 : 1.0)

  // Stable full-canvas bounds sentinel so BarIconContent's optical bounding-box
  // scaler never wobbles while the inner sync arrows rotate.
  Rectangle {
    anchors.fill: parent
    color: "transparent"
  }

  Item {
    id: arrowsClip
    anchors.fill: parent
    clip: true
    opacity: root.arrowsOpacity

    Behavior on opacity {
      NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic }
    }

    Shape {
      id: arrowsShape
      anchors.fill: parent
      antialiasing: true
      layer.enabled: true
      layer.samples: 4
      transformOrigin: Item.Center

      RotationAnimation on rotation {
        id: spinAnim
        from: 0
        to: 360
        duration: Style.duration(1400)
        loops: Animation.Infinite
        running: root.syncing && !root.crossed && !Style.reduceMotion
        onRunningChanged: {
          if (!running) arrowsShape.rotation = 0
        }
      }

      // Top-right clockwise arc (-145° -> -25°)
      ShapePath {
        fillColor: "transparent"
        strokeColor: root.color
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap

        PathAngleArc {
          centerX: root.cx
          centerY: root.cy
          radiusX: root.ringRadius
          radiusY: root.ringRadius
          startAngle: -145
          sweepAngle: 120
        }
      }

      // Bottom-left clockwise arc (35° -> 155°)
      ShapePath {
        fillColor: "transparent"
        strokeColor: root.color
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap

        PathAngleArc {
          centerX: root.cx
          centerY: root.cy
          radiusX: root.ringRadius
          radiusY: root.ringRadius
          startAngle: 35
          sweepAngle: 120
        }
      }

      ArrowHead { endAngleDeg: -25 }
      ArrowHead { endAngleDeg: 155 }
    }
  }

  // Diagonal strike line when Mutagen daemon is stopped or CLI is missing.
  Rectangle {
    visible: root.crossed
    anchors.centerIn: parent
    width: parent.width * 1.18
    height: Math.max(2, parent.height * 0.14)
    radius: height / 2
    color: root.color
    rotation: -45
  }

  // Compact urgent warning badge when any session has conflicts, errors, or disconnection.
  BorderSurface {
    visible: root.warning
    width: Math.max(7, parent.width * 0.42)
    height: width
    radius: width / 2
    color: root.badgeColor
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    borderSpec: Border.flat(Commons.Color.popups.background, 1)

    Text {
      anchors.centerIn: parent
      text: "!"
      textFormat: Text.PlainText
      color: Commons.Color.background
      font.family: Style.font.family
      font.pixelSize: Math.max(6, parent.height * 0.72)
      font.bold: true
    }
  }

  component ArrowHead: ShapePath {
    property real endAngleDeg: 0

    readonly property real rad: endAngleDeg * Math.PI / 180
    readonly property real rx: Math.cos(rad)
    readonly property real ry: Math.sin(rad)
    readonly property real tx: -Math.sin(rad)
    readonly property real ty: Math.cos(rad)
    readonly property real px: root.cx + root.ringRadius * rx
    readonly property real py: root.cy + root.ringRadius * ry
    readonly property real tipLen: root.iconSize * 0.17
    readonly property real backLen: root.iconSize * 0.06
    readonly property real spread: root.iconSize * 0.135
    readonly property real tuck: root.iconSize * 0.02

    fillColor: root.color
    strokeWidth: 0
    startX: px + tx * tipLen - rx * tuck
    startY: py + ty * tipLen - ry * tuck
    PathLine { x: px - tx * backLen + rx * spread; y: py - ty * backLen + ry * spread }
    PathLine { x: px - tx * backLen - rx * spread; y: py - ty * backLen - ry * spread }
    PathLine { x: px + tx * tipLen - rx * tuck; y: py + ty * tipLen - ry * tuck }
  }
}
