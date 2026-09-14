#!/bin/bash
#
# Чи працює LiveEdit AI Agent для клієнта.
#
# Кожна перевірка — те, що клієнт помітить: сервіс, сторінка продукту,
# завантаження плагіна, сертифікати. Один збій мережі на машині GitHub не
# повинен будити власника, тому кожну перевірку пробуємо тричі.
set -uo pipefail

API="${CHECK_API:-https://api.web-hub.online}"
SITE="${CHECK_SITE:-https://vlaszubenko.com}"
CERT_MIN_DAYS=14
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
failed=0

echo "| Перевірка | Результат |" >> "$SUMMARY"
echo "|---|---|" >> "$SUMMARY"

report() {
	local name="$1" ok="$2" note="$3"
	if [ "$ok" = "1" ]; then
		echo "| $name | ✅ $note |" >> "$SUMMARY"
		echo "OK   $name — $note"
	else
		echo "| $name | ❌ $note |" >> "$SUMMARY"
		echo "FAIL $name — $note"
		failed=1
	fi
}

# Тричі з паузою: повертає код і тіло останньої спроби.
fetch() {
	local url="$1" method="${2:-GET}" code body
	for attempt in 1 2 3; do
		# curl і на збої друкує код (000), тож запасне значення лише для порожнечі.
		if [ "$method" = "HEAD" ]; then
			code=$(curl -sS -o /dev/null -I -L -w '%{http_code}' --max-time 20 "$url" 2>/dev/null)
			body=""
		else
			body=$(curl -sS -L --max-time 20 -w '\n%{http_code}' "$url" 2>/dev/null)
			code=$(printf '%s' "$body" | tail -n1)
			body=$(printf '%s' "$body" | sed '$d')
		fi
		[ -z "$code" ] && code=000
		[ "$code" = "200" ] && break
		[ "$attempt" -lt 3 ] && sleep 15
	done
	FETCH_CODE="$code"
	FETCH_BODY="$body"
}

# 1. Сервіс: /health сам перевіряє базу, диск, ключі й нічні копії.
fetch "$API/health"
if [ "$FETCH_CODE" = "200" ] && printf '%s' "$FETCH_BODY" | grep -q '"ok":true'; then
	report "Сервіс (/health)" 1 "база, диск, налаштування, копії — в порядку"
else
	bad=$(printf '%s' "$FETCH_BODY" | grep -oE '"[a-z]+":false' | tr -d '"' | sed 's/:false//' | paste -sd, - 2>/dev/null)
	report "Сервіс (/health)" 0 "HTTP $FETCH_CODE${bad:+, не в порядку: $bad}"
fi

# 2. Тарифи: без них у плагіні немає кнопок оплати.
fetch "$API/api/v1/plans?site_url=https://status-check.invalid"
plans=$(printf '%s' "$FETCH_BODY" | grep -oE '"id":"(start|shop|agency)"' | wc -l | tr -d ' ')
if [ "$FETCH_CODE" = "200" ] && [ "$plans" = "3" ]; then
	report "Тарифи для плагіна" 1 "усі три на місці"
else
	report "Тарифи для плагіна" 0 "HTTP $FETCH_CODE, тарифів: $plans"
fi

# 3. Сторінка продукту, звідки приходять люди.
fetch "$SITE/products/livedit-ai-agent"
report "Сторінка продукту" "$( [ "$FETCH_CODE" = "200" ] && echo 1 || echo 0 )" "HTTP $FETCH_CODE"

# 4. Сам плагін можна завантажити.
fetch "$API/releases/livedit-ai-agent-pro.zip" HEAD
report "Завантаження плагіна" "$( [ "$FETCH_CODE" = "200" ] && echo 1 || echo 0 )" "HTTP $FETCH_CODE"

# 5. Сертифікати. Let's Encrypt оновлює за 30 днів до кінця; якщо лишилось
#    менше 14 — оновлення зламалось, і за два тижні сайт покаже попередження.
for host in ${CHECK_CERT_HOSTS:-api.web-hub.online vlaszubenko.com}; do
	end=$(echo | timeout 20 openssl s_client -connect "$host:443" -servername "$host" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
	if [ -z "$end" ]; then
		report "Сертифікат $host" 0 "не вдалося прочитати"
		continue
	fi
	days=$(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 ))
	report "Сертифікат $host" "$( [ "$days" -ge "$CERT_MIN_DAYS" ] && echo 1 || echo 0 )" "лишилось $days дн."
done

exit $failed
