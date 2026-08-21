# Running the tests from a console.
#
# There is deliberately no build target. RAD Studio 37.0 Personal edition
# refuses command-line compiling - both msbuild and dcc64 answer "This version
# of the product does not support command line compiling" - so building happens
# in the IDE and only running happens here.
#
# Written in the intersection of GNU make and the Embarcadero make that ships in
# Studio\bin, which is the one on PATH here: plain targets, no .PHONY, no
# conditionals. Recipes are cmd.exe syntax, not shell.

TESTS_EXE = tests\Win64\Debug\EventsLogTests.exe
TESTS_PROJECT = tests\EventsLogTests.dproj

help:
	@echo Targets:
	@echo   make test        run the unit tests, no pause, exit code says pass or fail
	@echo   make test-pause  the same run, waiting for Enter at the end
	@echo   make status      say when the test binary was last built
	@echo   make clean       delete the build output of both projects
	@echo.
	@echo Building is not available from a console in this edition.
	@echo Open $(TESTS_PROJECT) in the IDE and press Shift+F9 (Build).
	@echo.
	@echo A run started from the IDE waits on Enter and keeps the exe locked,
	@echo so close that console before rebuilding or the build fails with F2039.
	@echo make test does not pause, so it never leaves the file locked.

test:
	@if not exist $(TESTS_EXE) (echo Not built: $(TESTS_EXE)& echo Open $(TESTS_PROJECT) in the IDE and press Ctrl+F9 first.& exit /b 1)
	@echo Running the binary as it is. If a source changed since it was built,
	@echo rebuild in the IDE first - make cannot do it in this edition.
	@$(TESTS_EXE) --no-pause

status:
	@if not exist $(TESTS_EXE) (echo Not built: $(TESTS_EXE)& exit /b 1)
	@echo When the test binary was last built:
	@cmd /c "dir /t:w $(TESTS_EXE) | findstr /i EventsLogTests.exe"

test-pause:
	@if not exist $(TESTS_EXE) (echo Not built: $(TESTS_EXE)& exit /b 1)
	@$(TESTS_EXE)

clean:
	@if exist tests\Win64 rmdir /s /q tests\Win64
	@if exist tests\Win32 rmdir /s /q tests\Win32
	@if exist Win64 rmdir /s /q Win64
	@if exist Win32 rmdir /s /q Win32
	@echo Build output removed. Rebuild in the IDE.
