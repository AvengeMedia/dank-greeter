package main

import (
	"strings"
	"testing"
)

func TestCollectGreeterAppArmorDenialsSkipsComplainModeEntries(t *testing.T) {
	const journal = `audit: type=1400 audit(1.0:7): apparmor="ALLOWED" operation="open" profile="dms-greeter" name="/proc/1423/cgroup" pid=1423 comm="dms-greeter" requested_mask="r" denied_mask="r"
audit: type=1400 audit(1.0:8): apparmor="DENIED" operation="connect" profile="dms-greeter" name="/run/systemd/journal/stdout" pid=1423 comm="dms-greeter" requested_mask="wr" denied_mask="wr"
audit: type=1400 audit(1.0:8): apparmor="DENIED" operation="connect" profile="dms-greeter" name="/run/systemd/journal/stdout" pid=1423 comm="dms-greeter" requested_mask="wr" denied_mask="wr"
audit: type=1400 audit(1.0:9): apparmor="DENIED" operation="open" profile="cupsd" name="/etc/shadow" pid=99 comm="cupsd" requested_mask="r" denied_mask="r"
`
	var samples []string
	count := collectGreeterAppArmorDenials(journal, map[string]bool{}, &samples, 3)
	if count != 1 {
		t.Fatalf("count = %d, want 1", count)
	}
	if len(samples) != 1 || !strings.Contains(samples[0], "journal/stdout") {
		t.Fatalf("samples = %q", samples)
	}
}
