#!/bin/bash

pcregrep --color='auto' -n "[\x80-\xFF]" *.md; test $? -eq 1

