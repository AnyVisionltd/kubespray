#!/bin/bash

rm -rf pip_deps/*
pip download -r requirements.txt -d ./pip_deps/
