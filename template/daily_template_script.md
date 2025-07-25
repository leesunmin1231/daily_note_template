<%*
const { vault, workspace } = app;
const todayDate = new Date();

// 오늘 날짜 정보
const year = todayDate.getFullYear();
const monthNum = String(todayDate.getMonth() + 1).padStart(2, '0');
const monthName = todayDate.toLocaleString("en-US", { month: "short" });
const day = String(todayDate.getDate()).padStart(2, '0');
const weekday = todayDate.toLocaleString("en-US", { weekday: "short" });
const todayPath = `1-할일_기록/${year}-Daily/${monthNum}_${monthName}/${day}-${weekday}.md`;

// 어제 날짜 경로
const yesterday = new Date(todayDate);
yesterday.setDate(todayDate.getDate() - 1);
const yYear = yesterday.getFullYear();
const yMonthNum = String(yesterday.getMonth() + 1).padStart(2, '0');
const yMonthName = yesterday.toLocaleString("en-US", { month: "short" });
const yDay = String(yesterday.getDate()).padStart(2, '0');
const yWeekday = yesterday.toLocaleString("en-US", { weekday: "short" });
const yPath = `1-할일_기록/${yYear}-Daily/${yMonthNum}_${yMonthName}/${yDay}-${yWeekday}.md`;

// 섹션 추출 함수 (체크된 항목 제외)
function extractUncheckedItems(content, header) {
  const regex = new RegExp(`## ${header}[\\s\\S]*?(?=\\n## |$)`, 'g');
  const match = content.match(regex);
  if (!match) return '';

  const lines = match[0].split('\n').slice(1); // 제목 제외
  const result = [];

  let skip = false;
  let currentIndent = 0;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();

    const indent = line.search(/\S|$/); // 현재 줄의 들여쓰기 크기

    // 상위 체크된 항목이면 다음 줄들 (더 들여쓴)도 함께 스킵
    if (/^- \[x\]/.test(trimmed)) {
      skip = true;
      currentIndent = indent;
      continue;
    }

    // 스킵 중인데 현재 줄이 들여쓰기 수준이 작으면 스킵 종료
    if (skip && indent <= currentIndent) {
      skip = false;
    }

    if (!skip && trimmed !== '') {
      result.push(line);
    }
  }

  return result.join('\n').trim();
}


// 가장 최근 파일 찾기
async function findLatestDailyFile() {
  const files = app.vault.getMarkdownFiles();
  let latest = null;
  let latestDate = null;

  for (const file of files) {
    if (!file.path.startsWith("1-할일_기록/")) continue;
    const match = file.path.match(/(\d{4})-Daily\/(\d{2})_\w{3}\/(\d{2})-\w{3}\.md$/);
    if (match) {
      const [_, y, m, d] = match;
      const fileDate = new Date(`${y}-${m}-${d}`);
      if (fileDate < todayDate && (!latestDate || fileDate > latestDate)) {
        latestDate = fileDate;
        latest = file;
      }
    }
  }
  return latest;
}

// 섹션 초기값
let longTerm = '', inbox = '', inProgress = '';

const yFile = app.vault.getAbstractFileByPath(yPath);
const sourceFile = yFile ?? await findLatestDailyFile();

if (sourceFile) {
  const sourceContent = await app.vault.read(sourceFile);
  longTerm = extractUncheckedItems(sourceContent, '📌 Long term task');
  inbox = extractUncheckedItems(sourceContent, '📬 수신함 \\(Inbox\\)');
  inProgress = extractUncheckedItems(sourceContent, '✅ 진행 중 \\(In Progress\\)');
  someday = extractUncheckedItems(sourceContent, '⏳ 언젠가 \\(Someday / Maybe\\)');
}

// 템플릿 작성
const todayStr = `${year}-${monthNum}-${day}`;
const content =
`# 📅 업무 일지 - ${todayStr}
## 📌 Long term task
${longTerm || ''}

## 📬 수신함 (Inbox)
${inbox || ''}

## ✅ 진행 중 (In Progress)
${inProgress || '- [ ] 🔴🟡🔵'}

## ⏳ 언젠가 (Someday / Maybe)
${someday || ''}

## 💭 회고 / 메모\n`;

// 파일이 없으면 생성하고 열기
if (!await tp.file.exists(todayPath)) {
  await vault.create(todayPath, content);
}
workspace.openLinkText(todayPath, '', false);
%>
