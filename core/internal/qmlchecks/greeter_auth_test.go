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
	data, err := os.ReadFile("../../../quickshell/Modules/Greetd/GreeterContent.qml")
	if err != nil {
		t.Fatalf("read greeter QML: %v", err)
	}

	content := string(data)
	for _, required := range []string{
		"event.key === Qt.Key_Tab",
		"root.startAuthSession(false)",
		"pendingPasswordResponse",
		"greeterPamHasFaceAuth",
		"pam_sentinel",
		"Face recognition",
	} {
		if !strings.Contains(content, required) {
			t.Fatalf("greeter QML must contain %q for secondary auth trigger", required)
		}
	}
}
