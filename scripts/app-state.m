#import <AppKit/AppKit.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        // An empty NSRunningApplication result is only a trustworthy negative
        // when this process can see the user's GUI session. Finder is the
        // sentinel; otherwise fail closed instead of claiming ChatGPT quit.
        NSArray<NSRunningApplication *> *finder =
            [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.finder"];
        if (finder.count == 0) {
            puts("unknown");
            return 2;
        }

        NSArray<NSRunningApplication *> *codex =
            [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.openai.codex"];
        puts(codex.count == 0 ? "stopped" : "running");
        return 0;
    }
}
