CC = xcrun clang
CFLAGS = -Wall -Wextra -Werror -O2 -fobjc-arc
FRAMEWORKS = -framework Foundation -framework CoreGraphics -framework IOKit

.PHONY: all check clean
all: build/truetone-hold

build:
	mkdir -p build

build/truetone-hold: src/truetone-hold.m | build
	$(CC) $(CFLAGS) $(FRAMEWORKS) $< -o $@

build/test-dormant: tests/dormant.m src/truetone-hold.m | build
	$(CC) $(CFLAGS) $(FRAMEWORKS) $< -o $@

build/test-verification: tests/verification.m src/truetone-hold.m | build
	$(CC) $(CFLAGS) $(FRAMEWORKS) $< -o $@

build/test-transition: tests/transition.m src/truetone-hold.m | build
	$(CC) $(CFLAGS) $(FRAMEWORKS) $< -o $@

check: all build/test-dormant build/test-verification build/test-transition
	bash -n install.sh uninstall.sh
	./build/test-dormant
	./build/test-verification
	./build/test-transition

clean:
	rm -rf build
