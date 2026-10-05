package greeter

import (
	"context"
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"strings"

	"github.com/AvengeMedia/dank-greeter/core/internal/privesc"
)

var cacheRootLinkNames = []string{"settings.json", "session.json", "colors.json"}

// rootLinksInto lists cache-root entries that symlink into homeDir.
func rootLinksInto(cacheDir, homeDir string) []string {
	var links []string
	for _, name := range cacheRootLinkNames {
		path := filepath.Join(cacheDir, name)
		target, err := os.Readlink(path)
		if err != nil {
			continue
		}
		if !filepath.IsAbs(target) {
			target = filepath.Join(cacheDir, target)
		}
		if target == homeDir || strings.HasPrefix(target, homeDir+string(filepath.Separator)) {
			links = append(links, path)
		}
	}
	return links
}

type unlinkPlan struct {
	username  string
	userDir   string
	rootLinks []string
	slotOwned bool
}

func (p unlinkPlan) empty() bool {
	return p.userDir == "" && len(p.rootLinks) == 0
}

func (p unlinkPlan) needsPrivilege() bool {
	return len(p.rootLinks) > 0 || (p.userDir != "" && !p.slotOwned)
}

func planUnlink() (unlinkPlan, error) {
	currentUser, err := user.Current()
	if err != nil {
		return unlinkPlan{}, fmt.Errorf("failed to resolve current user: %w", err)
	}
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return unlinkPlan{}, fmt.Errorf("failed to get user home directory: %w", err)
	}
	plan := unlinkPlan{
		username:  currentUser.Username,
		rootLinks: rootLinksInto(GreeterCacheDir, homeDir),
	}
	userDir := userGreeterCacheDir(GreeterCacheDir, currentUser.Username)
	if st, statErr := os.Stat(userDir); statErr == nil && st.IsDir() {
		plan.userDir = userDir
		plan.slotOwned = CanSyncOwnUserGreeterProfile(currentUser.Username)
	}
	return plan, nil
}

func UnlinkNeedsPrivilege() bool {
	plan, err := planUnlink()
	return err == nil && plan.needsPrivilege()
}

func UnlinkTargets() ([]string, error) {
	plan, err := planUnlink()
	if err != nil {
		return nil, err
	}
	targets := append([]string{}, plan.rootLinks...)
	if plan.userDir != "" {
		targets = append(targets, plan.userDir)
	}
	return targets, nil
}

// UnlinkUserGreeterCache removes the current user's slot and any cache-root links into their home.
// greetd, PAM and other users' slots are untouched.
func UnlinkUserGreeterCache(logFunc func(string), sudoPassword string) error {
	if logFunc == nil {
		logFunc = func(string) {}
	}
	plan, err := planUnlink()
	if err != nil {
		return err
	}
	if plan.empty() {
		logFunc(fmt.Sprintf("ℹ Nothing is linked for %s", plan.username))
		return nil
	}
	if plan.userDir != "" {
		if plan.slotOwned {
			if err := os.RemoveAll(plan.userDir); err != nil {
				return fmt.Errorf("failed to remove %s: %w", plan.userDir, err)
			}
		} else if err := privesc.Run(context.Background(), sudoPassword, "rm", "-rf", plan.userDir); err != nil {
			return fmt.Errorf("failed to remove %s: %w", plan.userDir, err)
		}
		logFunc(fmt.Sprintf("✓ Removed per-user slot %s", plan.userDir))
	}
	for _, link := range plan.rootLinks {
		if err := privesc.Run(context.Background(), sudoPassword, "rm", "-f", link); err != nil {
			return fmt.Errorf("failed to remove %s: %w", link, err)
		}
		logFunc(fmt.Sprintf("✓ Removed %s", link))
	}
	return nil
}
