package greeter

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
)

type UserSlotState int

const (
	UserSlotMissing UserSlotState = iota
	UserSlotLive
	UserSlotSnapshot
	UserSlotBroken
)

func InspectUserSlot(cacheDir, username string) UserSlotState {
	sessionPath := filepath.Join(userGreeterCacheDir(cacheDir, username), "session.json")
	info, err := os.Lstat(sessionPath)
	if err != nil {
		return UserSlotMissing
	}
	if info.Mode()&os.ModeSymlink == 0 {
		return UserSlotSnapshot
	}
	if _, err := os.Stat(sessionPath); errors.Is(err, fs.ErrNotExist) {
		return UserSlotBroken
	}
	return UserSlotLive
}

func ListUserSlots(cacheDir string) ([]string, error) {
	entries, err := os.ReadDir(filepath.Join(cacheDir, "users"))
	if err != nil {
		return nil, err
	}
	names := []string{}
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		names = append(names, entry.Name())
	}
	sort.Strings(names)
	return names, nil
}
