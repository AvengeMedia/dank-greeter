package main

import (
	"fmt"
	"strings"

	"github.com/AvengeMedia/dank-greeter/core/internal/greeter"
)

func unlinkInTerminal(nonInteractive bool) error {
	shellCmd := "dms-greeter unlink"
	if nonInteractive {
		shellCmd += " --yes"
	}
	return runCommandInTerminal(shellCmd + `; echo; echo "Unlink finished. Closing in 3 seconds..."; sleep 3`)
}

func unlinkGreeter(nonInteractive bool) error {
	targets, err := greeter.UnlinkTargets()
	if err != nil {
		return err
	}
	if len(targets) == 0 {
		fmt.Println("ℹ Nothing is linked to the greeter for this user.")
		return nil
	}
	if !nonInteractive {
		fmt.Println("=== DMS Greeter Unlink ===")
		fmt.Println()
		fmt.Println("The login screen stops following your DMS settings. This removes:")
		for _, target := range targets {
			fmt.Printf("  • %s\n", target)
		}
		fmt.Println("greetd, PAM and other users are left alone. Run 'dms-greeter sync' to link again.")
		fmt.Print("\nContinue? [y/N]: ")
		var response string
		fmt.Scanln(&response)
		if strings.ToLower(strings.TrimSpace(response)) != "y" {
			fmt.Println("Aborted.")
			return nil
		}
	}
	return greeter.UnlinkUserGreeterCache(func(msg string) { fmt.Println(msg) }, "")
}
