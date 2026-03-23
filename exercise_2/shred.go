package shred

import (
	"crypto/rand"
	"io"
	"os"
)

func Shred(path string) error {
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	size := info.Size()
	for i := 0; i < 3; i++ {
		buf := make([]byte, size)
		_, err = io.ReadFull(rand.Reader, buf)
		if err != nil {
			return err
		}
		f, err := os.OpenFile(path, os.O_WRONLY, 0)
		if err != nil {
			return err
		}

		_, err = f.Write(buf)
		if err != nil {
			return err
		}
		err = f.Sync()
		if err != nil {
			return err
		}
		err = f.Close()
		if err != nil {
			return err
		}
	}
	return os.Remove(path)
}
