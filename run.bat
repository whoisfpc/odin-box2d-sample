@echo off
if [%1]==[] goto debug

if [%1]==[-speed] goto speed

:debug
echo run debug
odin run src -debug -sanitize:address
goto :done

:speed
echo run speed
odin run src -o:speed
goto :done

:done