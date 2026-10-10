_default:
    just --list

test: testUtilities runTests checkFlake

testUtilities:
    python3 -B util/test_utilities.py

runTests:
    nix shell -c sudo ./run-tests-in-container.sh

checkFlake:
    nix flake check

doc:
    nix run .#updateReadme

testReadme:
    nix run .#testReadme
