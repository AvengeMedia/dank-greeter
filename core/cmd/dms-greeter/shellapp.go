package main

import (
	"context"

	"github.com/AvengeMedia/dank-greeter/core/internal/shellembed"
	"github.com/AvengeMedia/dankgo/shellapp"
)

var shellApp = shellapp.New(shellapp.Config{
	ID:        "dms-greeter",
	EnvPrefix: "DMS_GREETER",
	QSAppID:   "com.danklinux.dms-greeter",
	Version:   Version,
	Embedded:  embeddedShell{},
	Boot:      bootPreviewBackend,
	ExtraEnv:  previewEnv,
})

// The greeter has no daemon: greetd supervises the real session, and the
// shellapp run path only serves in-session previews of the UI.
func bootPreviewBackend(context.Context) (shellapp.Backend, error) {
	return previewBackend{}, nil
}

type previewBackend struct{}

func (previewBackend) SocketPath() string { return "" }

func (previewBackend) Close() {}

func previewEnv(string) []string {
	return []string{"DMS_RUN_GREETER=1"}
}

type embeddedShell struct{}

func (embeddedShell) Available() bool { return shellembed.Available() }

func (embeddedShell) Extract(baseDir string) (string, error) { return shellembed.Extract(baseDir) }

func (embeddedShell) Prune(baseDir, keep string) { shellembed.Prune(baseDir, keep) }
