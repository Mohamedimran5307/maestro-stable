#!/bin/bash
# =============================================================================
# MAESTRO STABLE TEST RUNNER
# Collects device info, runs tests, generates JSON report, uploads to Google Drive
# =============================================================================

set -e

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="$SCRIPT_DIR/reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
APP_ID="org.digitalgreen.farmer.chat"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Create reports directory
mkdir -p "$REPORTS_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# GET TESTER NAME
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}           FARMERCHAT MAESTRO TEST SUITE${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if tester name is provided as argument or prompt
if [ -n "$1" ]; then
  TESTER_NAME="$1"
else
  echo -e "${CYAN}Enter your name (Tester Name):${NC} "
  read -r TESTER_NAME
  if [ -z "$TESTER_NAME" ]; then
    TESTER_NAME="Unknown_Tester"
  fi
fi
echo -e "Tester: ${YELLOW}$TESTER_NAME${NC}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# DETECT CONNECTED DEVICE
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${BLUE}Detecting connected device...${NC}"

DEVICE_ID=$(adb devices | grep -v 'List' | grep 'device$' | head -1 | awk '{print $1}')

if [ -z "$DEVICE_ID" ]; then
  echo -e "${RED}ERROR: No Android device connected!${NC}"
  echo "Please connect a device via USB and enable USB debugging."
  exit 1
fi

echo -e "Device ID: ${YELLOW}$DEVICE_ID${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# COLLECT DEVICE INFORMATION
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${BLUE}Collecting device information...${NC}"

DEVICE_MODEL=$(adb -s $DEVICE_ID shell getprop ro.product.model | tr -d '\r')
DEVICE_BRAND=$(adb -s $DEVICE_ID shell getprop ro.product.brand | tr -d '\r')
DEVICE_MANUFACTURER=$(adb -s $DEVICE_ID shell getprop ro.product.manufacturer | tr -d '\r')
ANDROID_VERSION=$(adb -s $DEVICE_ID shell getprop ro.build.version.release | tr -d '\r')
SDK_VERSION=$(adb -s $DEVICE_ID shell getprop ro.build.version.sdk | tr -d '\r')
DEVICE_NAME=$(adb -s $DEVICE_ID shell getprop ro.product.name | tr -d '\r')
BUILD_ID=$(adb -s $DEVICE_ID shell getprop ro.build.id | tr -d '\r')
SECURITY_PATCH=$(adb -s $DEVICE_ID shell getprop ro.build.version.security_patch | tr -d '\r')
DEVICE_SERIAL=$(adb -s $DEVICE_ID shell getprop ro.serialno | tr -d '\r')

echo -e "  Brand:           ${CYAN}$DEVICE_BRAND${NC}"
echo -e "  Model:           ${CYAN}$DEVICE_MODEL${NC}"
echo -e "  Android Version: ${CYAN}$ANDROID_VERSION (SDK $SDK_VERSION)${NC}"
echo -e "  Build ID:        ${CYAN}$BUILD_ID${NC}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# DISABLE OPPO VERIFICATION (for OPPO/Realme/OnePlus devices)
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${BLUE}Configuring device for testing...${NC}"
adb -s $DEVICE_ID shell settings put global verifier_verify_adb_installs 0 2>/dev/null || true
adb -s $DEVICE_ID shell settings put global package_verifier_enable 0 2>/dev/null || true
echo -e "  ${GREEN}✓ ADB verification disabled${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# ENSURE MAESTRO APKS ARE INSTALLED
# ─────────────────────────────────────────────────────────────────────────────
ensure_maestro_installed() {
  local MAESTRO_APP=$(adb -s $DEVICE_ID shell pm list packages 2>/dev/null | grep "dev.mobile.maestro$" || true)
  local MAESTRO_TEST=$(adb -s $DEVICE_ID shell pm list packages 2>/dev/null | grep "dev.mobile.maestro.test" || true)

  if [ -z "$MAESTRO_APP" ] || [ -z "$MAESTRO_TEST" ]; then
    echo -e "  ${YELLOW}Installing Maestro driver APKs...${NC}"
    cd /tmp
    unzip -o ~/.maestro/lib/maestro-client.jar maestro-app.apk maestro-server.apk 2>/dev/null || true
    if [ -z "$MAESTRO_APP" ]; then
      adb -s $DEVICE_ID install -r -g /tmp/maestro-app.apk &>/dev/null &
      sleep 5
      wait 2>/dev/null || true
    fi
    if [ -z "$MAESTRO_TEST" ]; then
      adb -s $DEVICE_ID install -r -g /tmp/maestro-server.apk &>/dev/null &
      sleep 5
      wait 2>/dev/null || true
    fi
    cd - >/dev/null
    echo -e "  ${GREEN}✓ Maestro APKs installed${NC}"
  else
    echo -e "  ${GREEN}✓ Maestro APKs already installed${NC}"
  fi
}

ensure_maestro_installed
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# DISMISS OPPO POPUP FUNCTION
# ─────────────────────────────────────────────────────────────────────────────
dismiss_oppo_popup() {
  for attempt in 1 2 3 4; do
    adb -s $DEVICE_ID shell uiautomator dump /sdcard/ui_check.xml 2>/dev/null
    local ui_dump=$(adb -s $DEVICE_ID shell cat /sdcard/ui_check.xml 2>/dev/null)
    
    if echo "$ui_dump" | grep -q "com.oplus.stdsp"; then
      if echo "$ui_dump" | grep -q "Continue installation"; then
        adb -s $DEVICE_ID shell input tap 360 1192 2>/dev/null
        sleep 3
      elif echo "$ui_dump" | grep -q "btn_finish"; then
        adb -s $DEVICE_ID shell input tap 360 1312 2>/dev/null
        sleep 1
      elif echo "$ui_dump" | grep -q "btn_navigation_close"; then
        adb -s $DEVICE_ID shell input tap 73 130 2>/dev/null
        sleep 1
      fi
    else
      break
    fi
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# SETUP TEST FUNCTION
# ─────────────────────────────────────────────────────────────────────────────
setup_test() {
  adb -s $DEVICE_ID shell am force-stop $APP_ID 2>/dev/null
  adb -s $DEVICE_ID shell "run-as $APP_ID sh -c 'rm -rf shared_prefs/* files/* cache/* databases/*'" 2>/dev/null || true
  adb -s $DEVICE_ID forward tcp:7001 tcp:7001 2>/dev/null
  adb -s $DEVICE_ID shell am start --activity-clear-task -n $APP_ID/org.digitalgreen.farmer.chatbot.MainActivity 2>/dev/null
  sleep 3
  dismiss_oppo_popup
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST CASE DEFINITIONS (ID, File, Name, Description - Stakeholder friendly)
# ─────────────────────────────────────────────────────────────────────────────
declare -a TEST_CASES=(
  "TC05|05_weather_widget_location|Weather Feature|User can view local weather forecast by sharing their location"
  "TC06|06_type_question_ai_response|Ask Questions (Type)|User can type a farming question and receive helpful AI-powered answers with follow-up suggestions"
  "TC08|08_home_feed_scroll|Home Screen Content|User can browse and scroll through farming tips and recommendations on the home screen"
  "TC11|11_listen_ai_response|Listen to Answers|User can listen to AI responses using text-to-speech audio playback"
  "TC25|25_settings_logout|Login and Logout|User can sign up with phone number, receive OTP, login successfully, and logout from settings"
)

# ─────────────────────────────────────────────────────────────────────────────
# RUN TESTS
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    RUNNING TEST CASES${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

TOTAL=0
PASSED=0
FAILED=0
TEST_RESULTS=""
START_TIME=$(date +%s)

for test_case in "${TEST_CASES[@]}"; do
  IFS='|' read -r TC_ID TC_FILE TC_NAME TC_DESC <<< "$test_case"
  TOTAL=$((TOTAL + 1))
  
  printf "${YELLOW}[%d/5]${NC} %-35s " "$TOTAL" "$TC_NAME"
  echo -ne "${BLUE}RUNNING...${NC}"
  
  # Setup test environment
  setup_test >/dev/null 2>&1
  
  # Background popup handler
  (
    for i in $(seq 1 20); do
      sleep 3
      dismiss_oppo_popup 2>/dev/null
    done
  ) &
  POPUP_PID=$!
  
  # Run test and capture output
  TEST_START=$(date +%s)
  OUTPUT=$(maestro --device $DEVICE_ID test \
    --env APP_ID=$APP_ID \
    --env LANGUAGE="English (Kenya)" \
    --env LANGUAGE_CODE=en \
    --env USER_NAME="Test Farmer" \
    --env SHORT_NAME=TF \
    --env WAIT_TIMEOUT=10000 \
    --env PHONE_NUMBER=7013733824 \
    --env OTP_CODE=1111 \
    "$SCRIPT_DIR/flows/home/${TC_FILE}.yaml" 2>&1)
  
  EXIT_CODE=$?
  TEST_END=$(date +%s)
  TEST_DURATION=$((TEST_END - TEST_START))
  
  kill $POPUP_PID 2>/dev/null || true
  
  # Clear line and print result
  echo -ne "\r"
  printf "${YELLOW}[%d/5]${NC} %-35s " "$TOTAL" "$TC_NAME"
  
  if [ $EXIT_CODE -eq 0 ]; then
    STATUS="PASSED"
    PASSED=$((PASSED + 1))
    echo -e "${GREEN}✓ PASSED${NC} (${TEST_DURATION}s)"
    ERROR_MESSAGE=""
  else
    STATUS="FAILED"
    FAILED=$((FAILED + 1))
    echo -e "${RED}✗ FAILED${NC} (${TEST_DURATION}s)"
    ERROR_MESSAGE=$(echo "$OUTPUT" | grep -A 2 "FAILED" | head -3 | tr '\n' ' ' | tr '"' "'" | sed 's/[[:cntrl:]]//g')
  fi
  
  # Build JSON for this test result (stakeholder-friendly)
  if [ -n "$TEST_RESULTS" ]; then
    TEST_RESULTS="$TEST_RESULTS,"
  fi
  
  # Convert duration to readable format
  if [ $TEST_DURATION -ge 60 ]; then
    DURATION_FRIENDLY="$((TEST_DURATION / 60))m $((TEST_DURATION % 60))s"
  else
    DURATION_FRIENDLY="${TEST_DURATION}s"
  fi
  
  # Status emoji for quick visual
  if [ "$STATUS" = "PASSED" ]; then
    STATUS_DISPLAY="✓ Passed"
  else
    STATUS_DISPLAY="✗ Failed"
  fi
  
  TEST_RESULTS="$TEST_RESULTS
    {
      \"id\": \"$TC_ID\",
      \"name\": \"$TC_NAME\",
      \"what_it_tests\": \"$TC_DESC\",
      \"result\": \"$STATUS_DISPLAY\",
      \"time_taken\": \"$DURATION_FRIENDLY\",
      \"issue\": \"$ERROR_MESSAGE\"
    }"
done

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))
MINS=$((TOTAL_DURATION / 60))
SECS=$((TOTAL_DURATION % 60))

# ─────────────────────────────────────────────────────────────────────────────
# GENERATE JSON REPORT (Stakeholder-friendly format)
# ─────────────────────────────────────────────────────────────────────────────
REPORT_FILE="$REPORTS_DIR/test_report_${TESTER_NAME// /_}_${TIMESTAMP}.json"
RUN_DATE=$(date +%Y-%m-%d)
RUN_TIME=$(date +%H:%M:%S)
RUN_DATE_FRIENDLY=$(date +"%B %d, %Y")
RUN_TIME_FRIENDLY=$(date +"%I:%M %p")

# Determine overall status
if [ $FAILED -eq 0 ]; then
  OVERALL_STATUS="All Tests Passed ✓"
  HEALTH_STATUS="Healthy"
else
  OVERALL_STATUS="$FAILED Test(s) Failed"
  HEALTH_STATUS="Needs Attention"
fi

cat > "$REPORT_FILE" << EOF
{
  "report_title": "FarmerChat App - Test Execution Report",
  "executive_summary": {
    "status": "$OVERALL_STATUS",
    "health": "$HEALTH_STATUS",
    "pass_rate": "$(echo "scale=0; $PASSED * 100 / $TOTAL" | bc)%",
    "tests_passed": $PASSED,
    "tests_failed": $FAILED,
    "total_tests": $TOTAL,
    "execution_time": "${MINS} minutes ${SECS} seconds"
  },
  "test_details": {
    "date": "$RUN_DATE_FRIENDLY",
    "time": "$RUN_TIME_FRIENDLY",
    "tested_by": "$TESTER_NAME",
    "device_used": "$DEVICE_BRAND $DEVICE_MODEL",
    "android_version": "Android $ANDROID_VERSION"
  },
  "test_cases": [$TEST_RESULTS
  ],
  "device_information": {
    "brand": "$DEVICE_BRAND",
    "model": "$DEVICE_MODEL",
    "android_version": "$ANDROID_VERSION",
    "device_id": "$DEVICE_ID"
  },
  "report_generated": "$RUN_DATE_FRIENDLY at $RUN_TIME_FRIENDLY"
}
EOF

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    TEST RESULTS SUMMARY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Tester:     ${CYAN}$TESTER_NAME${NC}"
echo -e "  Device:     ${CYAN}$DEVICE_BRAND $DEVICE_MODEL${NC}"
echo -e "  Android:    ${CYAN}$ANDROID_VERSION (SDK $SDK_VERSION)${NC}"
echo ""
echo -e "  Total:      ${YELLOW}$TOTAL${NC}"
echo -e "  Passed:     ${GREEN}$PASSED${NC}"
echo -e "  Failed:     ${RED}$FAILED${NC}"
echo -e "  Pass Rate:  ${CYAN}$(echo "scale=2; $PASSED * 100 / $TOTAL" | bc)%${NC}"
echo -e "  Duration:   ${YELLOW}${MINS}m ${SECS}s${NC}"
echo ""
echo -e "  Report:     ${CYAN}$REPORT_FILE${NC}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# UPLOAD TO GOOGLE DRIVE
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                  UPLOADING TO GOOGLE DRIVE${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if gdrive or rclone is available
if command -v gdrive &> /dev/null; then
  echo -e "${YELLOW}Uploading report using gdrive...${NC}"
  FOLDER_ID="${GDRIVE_FOLDER_ID:-}"
  if [ -n "$FOLDER_ID" ]; then
    gdrive files upload --parent "$FOLDER_ID" "$REPORT_FILE" && \
      echo -e "${GREEN}✓ Report uploaded to Google Drive${NC}" || \
      echo -e "${RED}✗ Failed to upload report${NC}"
  else
    gdrive files upload "$REPORT_FILE" && \
      echo -e "${GREEN}✓ Report uploaded to Google Drive (root folder)${NC}" || \
      echo -e "${RED}✗ Failed to upload report${NC}"
  fi
elif command -v rclone &> /dev/null; then
  echo -e "${YELLOW}Uploading report using rclone...${NC}"
  REMOTE_PATH="${RCLONE_REMOTE:-gdrive}:FarmerChat_Test_Reports"
  rclone copy "$REPORT_FILE" "$REMOTE_PATH" && \
    echo -e "${GREEN}✓ Report uploaded to Google Drive${NC}" || \
    echo -e "${RED}✗ Failed to upload report${NC}"
else
  echo -e "${YELLOW}Google Drive CLI not found.${NC}"
  echo ""
  echo "To enable automatic upload, install one of:"
  echo "  1. gdrive: https://github.com/glotlabs/gdrive"
  echo "  2. rclone: https://rclone.org/drive/"
  echo ""
  echo -e "Manual upload: ${CYAN}$REPORT_FILE${NC}"
  echo ""
  
  # Offer to open Google Drive in browser
  echo -e "${CYAN}Would you like to open Google Drive to upload manually? (y/n):${NC} "
  read -r OPEN_DRIVE
  if [ "$OPEN_DRIVE" = "y" ] || [ "$OPEN_DRIVE" = "Y" ]; then
    if [ "$(uname)" = "Darwin" ]; then
      open "https://drive.google.com/drive/folders/"
    elif [ "$(uname)" = "Linux" ]; then
      xdg-open "https://drive.google.com/drive/folders/" 2>/dev/null || echo "Please open https://drive.google.com manually"
    fi
  fi
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                    TEST RUN COMPLETE${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

exit $FAILED
