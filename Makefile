.PHONY: app install watch clean

# Build, install to ~/Applications and launch.
app:
	./build.sh

# Build and install without launching.
install:
	./build.sh --no-open

# Rebuild automatically whenever .rebuild is touched.
watch:
	./scripts/dev-watch.sh

clean:
	rm -rf .build build build.log
