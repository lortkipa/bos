import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation {
    id: presentation

    function nextSlide() { presentation.goToNextSlide(); }

    Timer {
        id: advanceTimer
        interval: 8000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: nextSlide()
    }

    Slide {
        Rectangle { anchors.fill: parent; color: "#F4F4F6" }
        Image { id: logo1; source: "logo.png"; width: 96; height: 96
                anchors.horizontalCenter: parent.horizontalCenter; y: parent.height * 0.22 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; anchors.top: logo1.bottom; anchors.topMargin: 24
               text: "Welcome to bOS"; font.pixelSize: 30; font.weight: Font.DemiBold; color: "#2C2C30" }
        Text { anchors.horizontalCenter: parent.horizontalCenter; y: parent.height * 0.62; width: parent.width * 0.7
               horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: "#6E6E76"; font.pixelSize: 16
               text: "A calm, clean desktop. Your apps live in the dock, the menu bar sits up top." }
    }
    Slide {
        Rectangle { anchors.fill: parent; color: "#F4F4F6" }
        Text { anchors.centerIn: parent; width: parent.width * 0.7; horizontalAlignment: Text.AlignHCenter
               wrapMode: Text.WordWrap; color: "#2C2C30"; font.pixelSize: 20
               text: "Press <b>Super</b> to open the app menu.<br/>Drag apps onto the dock to keep them there." }
    }
    Slide {
        Rectangle { anchors.fill: parent; color: "#F4F4F6" }
        Text { anchors.centerIn: parent; width: parent.width * 0.7; horizontalAlignment: Text.AlignHCenter
               wrapMode: Text.WordWrap; color: "#2C2C30"; font.pixelSize: 20
               text: "Built on Ubuntu LTS: thousands of apps are one <tt>sudo apt install</tt> away." }
    }

    function onActivate() { presentation.currentSlide = 0; }
    function onLeave() { }
}
