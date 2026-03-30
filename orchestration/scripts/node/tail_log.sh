#!/bin/bash
# Expects: LOG_FILE — absolute path to log file
[ -f "${LOG_FILE}" ] && tail -n 500 "${LOG_FILE}" || echo WAITING_FOR_LOG
