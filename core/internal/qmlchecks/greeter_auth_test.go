package qmlchecks

import (
	"os"
	"strings"
	"testing"
)

func TestGreeterExternalAuthStatusUsesEffectiveFingerprintAvailability(t *testing.T) {
	data, err := os.ReadFile("../../../quickshell/Modules/Greetd/GreeterContent.qml")
	if err != nil {
		t.Fatalf("read greeter QML: %v", err)
	}

	content := string(data)
	for _, required := range []string{
		"readonly property bool greeterPamHasExternalAuth: greeterPamHasFprint || greeterPamHasU2f",
		"if (greeterPamHasFprint && greeterPamHasU2f)",
		"if (greeterPamHasFprint)",
	} {
		if !strings.Contains(content, required) {
			t.Fatalf("greeter external-auth status must contain %q", required)
		}
	}
}

func TestGreeterExternalAuthTabTriggerAndFaceSupport(t *testing.T) {
	content, err := os.ReadFile("../../../quickshell/Modules/Greetd/GreeterContent.qml")
	if err != nil {
		t.Fatalf("read greeter QML: %v", err)
	}
	for _, required := range []string{
		"greeterPamHasFaceAuth",
		"pam_sentinel",
	} {
		if !strings.Contains(string(content), required) {
			t.Fatalf("greeter QML must contain %q for face auth support", required)
		}
	}

	widget, err := os.ReadFile("../../../quickshell/Modules/Greetd/GreeterAuthWidget.qml")
	if err != nil {
		t.Fatalf("read greeter auth widget QML: %v", err)
	}
	for _, required := range []string{
		"event.key === Qt.Key_Tab",
		"root.host.startAuthSession(false)",
		"pendingPasswordResponse",
		"Face recognition",
	} {
		if !strings.Contains(string(widget), required) {
			t.Fatalf("greeter auth widget must contain %q for secondary auth trigger", required)
		}
	}
}
