package shred

import (
	"os"
	"path/filepath"
	"testing"
)

// TestNotExistAfterShred verifies that a normal file with content is deleted
// after Shred completes successfully.
func TestNotExistAfterShred(t *testing.T) {
	f, err := os.CreateTemp("", "testfile-*")
	if err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}
	path := f.Name()
	_, err = f.Write([]byte("hello Shred!"))
	if err != nil {
		t.Fatalf("failed to write to temp file : %v", err)
	}
	f.Close()
	if err := Shred(path); err != nil {
		t.Fatalf("Shred failed: %v", err)
	}
	_, err = os.Stat(path)
	if !os.IsNotExist(err) {
		t.Errorf("file should not exist after Shred")
	}
}

// TestShredNonExistFile verifies that Shred returns a not-exist error
// when the given path does not exist on the filesystem.
func TestShredNonExistFile(t *testing.T) {
	if err := Shred("/some/non/exist/file"); !os.IsNotExist(err) {
		t.Errorf("expected NotExist Error, got %v", err)
	}
}

// TestShredEmptyFile verifies that Shred handles a zero-byte file without error
// and deletes it afterwards. make([]byte, 0) and io.ReadFull on an empty buffer
// are both no-ops, so no special case is needed in the implementation.
func TestShredEmptyFile(t *testing.T) {
	f, err := os.CreateTemp("", "testfile-empty-*")
	if err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}
	path := f.Name()
	f.Close()

	if err := Shred(path); err != nil {
		t.Fatalf("Shred failed on empty file: %v", err)
	}
	_, err = os.Stat(path)
	if !os.IsNotExist(err) {
		t.Errorf("file should not exist after Shred")
	}
}

// TestShredNoPermission verifies that Shred returns a permission error when the
// file mode is 000. After confirming the error, the test restores permissions
// and shreds the file to ensure cleanup. Note: this test will not behave as
// expected when run as root, since root bypasses file permission checks.
func TestShredNoPermission(t *testing.T) {
	f, err := os.CreateTemp("", "testfile-noperm-*")
	if err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}
	path := f.Name()
	f.Close()

	if err := os.Chmod(path, 0000); err != nil {
		t.Fatalf("failed to chmod: %v", err)
	}

	defer func() {
		os.Remove(path)
	}()

	if err := Shred(path); !os.IsPermission(err) {
		t.Errorf("expected Permission Error, got %v", err)
	}

	if err := os.Chmod(path, 0600); err != nil {
		t.Fatalf("failed to chmod: %v", err)
	}

	if err := Shred(path); err != nil {
		t.Fatalf("Shred failed on file: %v", err)
	}
	_, err = os.Stat(path)
	if !os.IsNotExist(err) {
		t.Errorf("file should not exist after Shred")
	}
}

// TestShredDirectory verifies that passing a directory path returns an error.
// On Linux, opening a directory with O_WRONLY returns EISDIR.
func TestShredDirectory(t *testing.T) {
	dir, err := os.MkdirTemp("", "testdir-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.Remove(dir)

	if err := Shred(dir); err == nil {
		t.Errorf("expected error when shredding a directory, got nil")
	}
}

// TestShredSymlink documents the current behavior of Shred on a symlink:
// - the target file is overwritten 3 times with random data
// - the symlink itself is removed (not the target)
// - the target file still exists after Shred, with its content overwritten
// This may be surprising to callers who expect the target to be deleted.
func TestShredSymlink(t *testing.T) {
	// Create the target file
	target, err := os.CreateTemp("", "testfile-target-*")
	if err != nil {
		t.Fatalf("failed to create target file: %v", err)
	}
	if _, err := target.Write([]byte("sensitive data")); err != nil {
		t.Fatalf("failed to write to target: %v", err)
	}
	target.Close()
	targetPath := target.Name()
	defer os.Remove(targetPath)

	// Create a symlink pointing to the target
	linkPath := filepath.Join(os.TempDir(), "testfile-symlink")
	if err := os.Symlink(targetPath, linkPath); err != nil {
		t.Fatalf("failed to create symlink: %v", err)
	}

	if err := Shred(linkPath); err != nil {
		t.Fatalf("Shred failed on symlink: %v", err)
	}

	// The symlink should be removed
	_, err = os.Lstat(linkPath)
	if !os.IsNotExist(err) {
		t.Errorf("symlink should not exist after Shred")
		os.Remove(linkPath)
	}

	// The target file still exists (only the symlink was removed by os.Remove)
	_, err = os.Stat(targetPath)
	if os.IsNotExist(err) {
		t.Errorf("target file should still exist after shredding symlink; Shred only removes the symlink")
	}
}
