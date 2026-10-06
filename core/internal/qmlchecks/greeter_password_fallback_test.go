package qmlchecks

import (
	"context"
	"os/exec"
	"testing"
	"time"
)

func TestFaceAuthWaitPreservesPasswordFallback(t *testing.T) {
	node, err := exec.LookPath("node")
	if err != nil {
		t.Skip("Node.js is required to exercise the greeter's JavaScript authentication flow")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, node, "testdata/greeter_password_fallback.cjs",
		"../../../quickshell/Modules/Greetd/GreeterContent.qml")
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("greeter password fallback: %v\n%s", err, output)
	}
}
