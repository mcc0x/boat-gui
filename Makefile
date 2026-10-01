.PHONY: app build install test watch clean

app:
	./build.sh

build:
	./build.sh --build-only

install:
	./build.sh --no-open

test:
	./scripts/test.sh
	./scripts/test-build.sh

watch:
	./scripts/dev-watch.sh

clean:
	rm -rf .build build build.log
