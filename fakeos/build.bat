@echo off
call "C:\Users\wetca\data\silly  code\architecture\NotSoTiny\programming\toolchain\assemble.bat" -o -d test_shell.asm test_shell.oex test_shell.entry
call "C:\Users\wetca\data\silly  code\architecture\NotSoTiny\programming\toolchain\link.bat" -l test_shell.oex test_shell.dat
