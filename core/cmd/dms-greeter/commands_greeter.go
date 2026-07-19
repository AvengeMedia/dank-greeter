package main

import (
	"fmt"
	"os"

	"github.com/AvengeMedia/dank-greeter/core/internal/greeter"
	sharedpam "github.com/AvengeMedia/dank-greeter/core/internal/pam"
	"github.com/AvengeMedia/dankgo/log"
	"github.com/spf13/cobra"
)

var (
	greeterConfigSyncFn = greeter.SyncDMSConfigs
	sharedAuthSyncFn    = sharedpam.SyncAuthConfig
	greeterIsNixOSFn    = greeter.IsNixOS
)

var greeterInstallCmd = &cobra.Command{
	Use:     "install",
	Short:   "Install and configure DMS greeter",
	Long:    "Install greetd and configure it to use dms-greeter as the greeter interface",
	PreRunE: preRunGreeterMutation,
	Run: func(cmd *cobra.Command, args []string) {
		yes, _ := cmd.Flags().GetBool("yes")
		term, _ := cmd.Flags().GetBool("terminal")
		if term {
			installCmd := "dms-greeter install"
			if yes {
				installCmd += " --yes"
			}
			installCmd += "; echo; echo \"Install finished. Closing in 3 seconds...\"; sleep 3"
			if err := runCommandInTerminal(installCmd); err != nil {
				log.Fatalf("Error launching install in terminal: %v", err)
			}
			return
		}
		if err := installGreeter(yes); err != nil {
			log.Fatalf("Error installing greeter: %v", err)
		}
	},
}

var greeterSyncCmd = &cobra.Command{
	Use:   "sync",
	Short: "Sync DMS theme and settings with greeter",
	Long:  "Synchronize your current user's DMS theme, settings, and wallpaper configuration with the login greeter screen. Also updates a per-user cache slot at users/<username>/ for multi-account greeter theme preview.\n\nUse --profile on secondary accounts to sync only your own users/<username>/ slot without sudo or greetd changes.",
	PreRunE: func(cmd *cobra.Command, args []string) error {
		if err := rejectNixOSGreeterMutation(cmd); err != nil {
			return err
		}
		profile, _ := cmd.Flags().GetBool("profile")
		if profile {
			return nil
		}
		return preRunPrivileged(cmd, args)
	},
	Run: func(cmd *cobra.Command, args []string) {
		yes, _ := cmd.Flags().GetBool("yes")
		auth, _ := cmd.Flags().GetBool("auth")
		local, _ := cmd.Flags().GetBool("local")
		profile, _ := cmd.Flags().GetBool("profile")
		autologinOnly, _ := cmd.Flags().GetBool("autologin")
		term, _ := cmd.Flags().GetBool("terminal")
		if term {
			if err := syncInTerminal(yes, auth, local, profile, autologinOnly); err != nil {
				log.Fatalf("Error launching sync in terminal: %v", err)
			}
			return
		}
		if autologinOnly {
			if err := syncGreeterAutoLoginOnly(); err != nil {
				log.Fatalf("Error syncing greeter auto-login: %v", err)
			}
			return
		}
		if err := syncGreeter(yes, auth, local, profile); err != nil {
			log.Fatalf("Error syncing greeter: %v", err)
		}
	},
}

var greeterLaunchSessionCmd = &cobra.Command{
	Use:    "launch-session",
	Short:  "Launch a remembered greeter session",
	Hidden: true,
	Run: func(cmd *cobra.Command, args []string) {
		sessionID, _ := cmd.Flags().GetString("session-id")
		fromMemory, _ := cmd.Flags().GetBool("from-memory")
		cacheDir, _ := cmd.Flags().GetString("cache-dir")

		if fromMemory {
			homeDir, err := os.UserHomeDir()
			if err != nil {
				log.Fatalf("failed to get user home directory: %v", err)
			}
			if err := greeter.LaunchSessionFromMemory(cacheDir, homeDir); err != nil {
				log.Fatalf("failed to launch remembered greeter session: %v", err)
			}
			return
		}

		if sessionID == "" {
			log.Fatal("missing --session-id or --from-memory")
		}
		if err := greeter.LaunchSessionByID(sessionID); err != nil {
			log.Fatalf("failed to launch greeter session %q: %v", sessionID, err)
		}
	},
}

var greeterEnableCmd = &cobra.Command{
	Use:     "enable",
	Short:   "Enable DMS greeter in greetd config",
	Long:    "Configure greetd to use dms-greeter as the greeter",
	PreRunE: preRunGreeterMutation,
	Run: func(cmd *cobra.Command, args []string) {
		yes, _ := cmd.Flags().GetBool("yes")
		term, _ := cmd.Flags().GetBool("terminal")
		if term {
			enableCmd := "dms-greeter enable"
			if yes {
				enableCmd += " --yes"
			}
			enableCmd += "; echo; echo \"Enable finished. Closing in 3 seconds...\"; sleep 3"
			if err := runCommandInTerminal(enableCmd); err != nil {
				log.Fatalf("Error launching enable in terminal: %v", err)
			}
			return
		}
		if err := enableGreeter(yes); err != nil {
			log.Fatalf("Error enabling greeter: %v", err)
		}
	},
}

var greeterStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Check greeter sync status",
	Long:  "Check the status of greeter installation and configuration sync",
	Run: func(cmd *cobra.Command, args []string) {
		if err := checkGreeterStatus(); err != nil {
			log.Fatalf("Error checking greeter status: %v", err)
		}
	},
}

var greeterUninstallCmd = &cobra.Command{
	Use:     "uninstall",
	Short:   "Remove DMS greeter configuration and restore previous display manager",
	Long:    "Disable greetd, remove DMS managed configs, and restore the system to its pre-DMS-greeter state",
	PreRunE: preRunGreeterMutation,
	Run: func(cmd *cobra.Command, args []string) {
		yes, _ := cmd.Flags().GetBool("yes")
		term, _ := cmd.Flags().GetBool("terminal")
		if term {
			uninstallCmd := "dms-greeter uninstall"
			if yes {
				uninstallCmd += " --yes"
			}
			uninstallCmd += "; echo; echo \"Uninstall finished. Closing in 3 seconds...\"; sleep 3"
			if err := runCommandInTerminal(uninstallCmd); err != nil {
				log.Fatalf("Error launching uninstall in terminal: %v", err)
			}
			return
		}
		if err := uninstallGreeter(yes); err != nil {
			log.Fatalf("Error uninstalling greeter: %v", err)
		}
	},
}

func init() {
	greeterInstallCmd.Flags().BoolP("yes", "y", false, "Non-interactive: skip confirmation prompt")
	greeterInstallCmd.Flags().BoolP("terminal", "t", false, "Run in a new terminal (for entering sudo password)")
	greeterEnableCmd.Flags().BoolP("yes", "y", false, "Non-interactive: skip confirmation prompt")
	greeterEnableCmd.Flags().BoolP("terminal", "t", false, "Run in a new terminal (for entering sudo password)")
	greeterUninstallCmd.Flags().BoolP("yes", "y", false, "Non-interactive: skip confirmation prompt")
	greeterUninstallCmd.Flags().BoolP("terminal", "t", false, "Run in a new terminal (for entering sudo password)")

	greeterSyncCmd.Flags().BoolP("yes", "y", false, "Non-interactive mode: skip prompts, use defaults (for UI)")
	greeterSyncCmd.Flags().BoolP("terminal", "t", false, "Run sync in a new terminal (for entering sudo password); terminal auto-closes when done")
	greeterSyncCmd.Flags().BoolP("auth", "a", false, "Configure PAM for fingerprint and U2F (adds both if modules exist); overrides UI toggles")
	greeterSyncCmd.Flags().BoolP("local", "l", false, "Developer mode: force greetd config to use a local quickshell checkout path")
	greeterSyncCmd.Flags().BoolP("profile", "p", false, "Sync only your per-user greeter slot (no sudo; for secondary accounts)")
	greeterSyncCmd.Flags().Bool("autologin", false, "Apply only greeter auto-login on startup settings to greetd (no theme or auth sync)")

	greeterLaunchSessionCmd.Flags().String("session-id", "", "Desktop session id to launch")
	greeterLaunchSessionCmd.Flags().Bool("from-memory", false, "Resolve the session id from greeter memory")
	greeterLaunchSessionCmd.Flags().String("cache-dir", greeter.GreeterCacheDir, "Greeter cache directory")

	rootCmd.AddCommand(greeterInstallCmd, greeterSyncCmd, greeterEnableCmd, greeterStatusCmd, greeterUninstallCmd, greeterLaunchSessionCmd)
}

func rejectNixOSGreeterMutation(cmd *cobra.Command) error {
	if !greeterIsNixOSFn() {
		return nil
	}

	return fmt.Errorf("dms-greeter %s is disabled on NixOS because the greeter is managed declaratively\nConfigure the DMS greeter in your NixOS module, then apply the change with your normal nixos-rebuild workflow", normalizeCommandSpec(cmd.CommandPath()))
}

func preRunGreeterMutation(cmd *cobra.Command, args []string) error {
	if err := rejectNixOSGreeterMutation(cmd); err != nil {
		return err
	}
	return preRunPrivileged(cmd, args)
}

func syncGreeterConfigsAndAuth(compositor string, logFunc func(string), options sharedpam.SyncAuthOptions, beforeAuth func()) error {
	if err := greeterConfigSyncFn(compositor, logFunc, ""); err != nil {
		return err
	}
	if beforeAuth != nil {
		beforeAuth()
	}
	return sharedAuthSyncFn(logFunc, "", options)
}
