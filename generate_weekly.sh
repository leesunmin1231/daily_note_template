#!/usr/bin/env bash

# 필수: macOS 사용자는 coreutils 설치 필요
DATE_CMD="date"
if command -v gdate &> /dev/null; then
  DATE_CMD="gdate"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  echo "[X] macOS에서는 'brew install coreutils'로 gdate를 설치하세요."
  exit 1
fi

# 날짜 유효성 검사
is_valid_date() {
  local date="$1"
  $DATE_CMD -d "$date" '+%Y-%m-%d' > /dev/null 2>&1
  return $?
}

# ISO 주차 구하기 (ISO 연도, 주차)
get_week_number() {
  local full_date="$1"
  $DATE_CMD -d "$full_date" '+%G %V'
}

# 📦 블록 추출 함수
extract_block_items() {
  local block_start="$1"
  local block_end="$2"
  local file="$3"
  local filter="$4"

  awk -v start="$block_start" -v end="$block_end" -v filter="$filter" '
    BEGIN { in_block=0; printing=0 }
    $0 ~ start { in_block=1; next }
    $0 ~ end && in_block == 1 { exit }
    in_block == 1 {
      if ($0 ~ /^[[:space:]]*-[[:space:]]\[[ xX]\]/) {
        printing=1
      }
      if (printing) {
        if (filter == "checked" && $0 ~ /^[[:space:]]*-[[:space:]]\[[xX]\]/) {
          sub(/\[[xX]\]/, "[x] ")
          print
        } else if (filter == "all") {
          if ($0 ~ /^[[:space:]]*-[[:space:]]\[ \]/) {
            sub(/\[ \]/, "[ ] ")
          } else if ($0 ~ /^[[:space:]]*-[[:space:]]\[[xX]\]/) {
            sub(/\[[xX]\]/, "[x] ")
          }
          print
        }
      }
    }
  ' "$file"
}

extract_memo_block() {
  local file="$1"
  awk '
    /^## 💭 회고[[:space:]]*\/[[:space:]]*메모/ { in_block=1; next }
    /^## / && in_block { exit }
    in_block { print }
  ' "$file"
}

# 인자 파싱
FORCE_ALL=false
if [[ "$1" == "-a" || "$1" == "all" ]]; then
  FORCE_ALL=true
  shift
fi

if [[ "$1" =~ ^[0-9]{4}$ ]]; then
  YEAR="$1"
else
  YEAR="$($DATE_CMD '+%Y')"
fi

DAILY_DIR="1-할일_기록/${YEAR}-Daily"
WEEKLY_DIR="1-할일_기록/${YEAR}-Weekly"
mkdir -p "$WEEKLY_DIR"
TMP_DIR=$(mktemp -d)
WEEK_IDS_FILE="$TMP_DIR/week_ids.txt"
> "$WEEK_IDS_FILE"

declare -A blocks
declare -a week_date_keys

# 이번달과 저번달 폴더만 타겟으로 잡기
TODAY=$($DATE_CMD '+%Y-%m-01')
LAST_MONTH=$($DATE_CMD -d "$TODAY -1 month" '+%m_%b')
THIS_MONTH=$($DATE_CMD -d "$TODAY" '+%m_%b')

# 파일 리스트
if [ "$FORCE_ALL" = true ]; then
  FILES=$(find "$DAILY_DIR" -type f -name "*.md")
else
  FILES=$(find "$DAILY_DIR" \( -path "*/$LAST_MONTH/*.md" -o -path "*/$THIS_MONTH/*.md" \))
fi

# 파일 순회
while read -r FILE; do
  BASENAME=$(basename "$FILE")
  DIRNAME=$(basename "$(dirname "$FILE")")
  DAY_NUM=$(echo "$BASENAME" | cut -d '-' -f 1)
  MONTH_NUM=$(echo "$DIRNAME" | cut -d '_' -f 1)

  DAY_NUM=$((10#$DAY_NUM))
  MONTH_NUM=$((10#$MONTH_NUM))
  FULL_DATE="$YEAR-$(printf "%02d" "$MONTH_NUM")-$(printf "%02d" "$DAY_NUM")"

  if ! is_valid_date "$FULL_DATE"; then
    continue
  fi

  read ISO_YEAR ISO_WEEK <<< "$(get_week_number "$FULL_DATE")"
  ISO_WEEK=$((10#$ISO_WEEK))

  WEEK_ID="${ISO_YEAR}-$(printf "%02d" "$MONTH_NUM")-W$(printf "%02d" "$ISO_WEEK")"
  DATE_KEY=$($DATE_CMD -d "$FULL_DATE" '+%Y-%m-%d')
  COMPOUND_KEY="${WEEK_ID}|${DATE_KEY}"

  if ! grep -qx "$WEEK_ID" "$WEEK_IDS_FILE"; then
    echo "$WEEK_ID" >> "$WEEK_IDS_FILE"
  fi

  MONTH_PADDED=$(printf "%02d" "$MONTH_NUM")
  DAY_PADDED=$(printf "%02d" "$DAY_NUM")

  blocks["$COMPOUND_KEY"]=$(
  {
    echo "### ${MONTH_PADDED}월 ${DAY_PADDED}일 ($BASENAME)"
    extract_block_items "## 📬 수신함" "## " "$FILE" "checked" || echo "- (없음)"
    extract_block_items "## ✅ 진행 중" "## " "$FILE" "all" || echo "- (없음)"
    extract_block_items "## 📦 완료 내역" "## " "$FILE" "all" || echo "- (없음)"
  }
  )

  week_date_keys+=("$COMPOUND_KEY")
done <<< "$FILES"

# 주차별 정리
sort "$WEEK_IDS_FILE" | while read -r WEEK_ID; do
  SUMMARY_FILE="$WEEKLY_DIR/weekly-${WEEK_ID}.md"
  if [ "$FORCE_ALL" = false ] && [ -f "$SUMMARY_FILE" ]; then continue; fi

  WEEK_YEAR=$(echo "$WEEK_ID" | cut -d '-' -f 1)
  WEEK_MONTH=$(echo "$WEEK_ID" | cut -d '-' -f 2 | sed 's/^0*//')
  WEEK_NUM=$(echo "$WEEK_ID" | cut -d '-' -f 3 | sed 's/W0*//')
  MEMOS=""

  {
    echo "# 📋 ${WEEK_YEAR}년 ${WEEK_MONTH}월 ${WEEK_NUM}주차 업무 요약"
    echo ""
    echo "## 📅 일별 요약"
    for KEY in $(printf "%s\n" "${week_date_keys[@]}" | grep "^$WEEK_ID|" | sort -t '|' -k2); do
      echo "${blocks[$KEY]}"
      echo ""

      FILE_DATE=$(echo "$KEY" | cut -d '|' -f 2)
      MEMO_FILE="$DAILY_DIR/$(LC_TIME=C $DATE_CMD -d "$FILE_DATE" '+%m_%b')/$(LC_TIME=C $DATE_CMD -d "$FILE_DATE" '+%d-%a').md"
      if [ -f "$MEMO_FILE" ]; then
        MEMO=$(extract_memo_block "$MEMO_FILE")
        if [ -n "$MEMO" ]; then
          MEMO_DAY=$($DATE_CMD -d "$FILE_DATE" '+%m월 %d일')
          MEMOS+="**${MEMO_DAY}**\n${MEMO}\n\n"
        fi
      fi
    done

    if [ -n "$MEMOS" ]; then
      echo ""
      echo "## 💭 주간 회고"
      echo -e "$MEMOS"
    fi
  } > "$SUMMARY_FILE"

  echo "[+] 생성 완료: $SUMMARY_FILE"
done

rm -r "$TMP_DIR"
