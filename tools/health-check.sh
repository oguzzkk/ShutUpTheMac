#!/bin/bash
# Uzun süreli sağlık ölçümü.
#
# Menü çubuğu uygulamaları günlerce açık kalır; sorunlar da genelde ilk dakikada değil,
# saatler sonra görünür: sızan bellek, biriken iş parçacıkları, sessizce duran ses yolu.
# Bu betik düzenli örnek alır ve sapmaları işaretler.
#
#   ./tools/health-check.sh              30 sn aralıkla, sonsuza kadar
#   ./tools/health-check.sh 60 480       60 sn aralıkla 480 örnek (8 saat)
#
# Çıktı: tools/health-log.tsv (tablo hâlinde, sonradan incelenebilir)

set -u
INTERVAL="${1:-30}"
SAMPLES="${2:-0}"            # 0 = sınırsız
LOG="$(cd "$(dirname "$0")/.." && pwd)/tools/health-log.tsv"
SHUTUP="$(cd "$(dirname "$0")/.." && pwd)/.build/release/shutup"
[ -x "$SHUTUP" ] || SHUTUP="/Applications/Shut Up The Mac.app/Contents/Resources/shutup"

status_field() { "$SHUTUP" status 2>/dev/null | grep "\"$1\"" | head -1 | grep -oE '[0-9]+(\.[0-9]+)?' | head -1; }

[ -f "$LOG" ] || printf "zaman\tpid\tcpu\tbellek_mb\tthread\ttanitici\ttap\tcagri\tkesilme\tcokme\tnot\n" > "$LOG"

first_rss=""; first_threads=""; prev_callbacks=""; prev_taps=""; prev_pid=""; count=0
crash_base=$(ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -ci "shutup")

echo "izleme başladı — aralık ${INTERVAL}sn, günlük: $LOG"
while :; do
    pid=$(pgrep -f "Shut Up The Mac.app/Contents/MacOS" | head -1)
    now=$(date "+%H:%M:%S")
    note=""

    if [ -z "$pid" ]; then
        printf "%s\t-\t-\t-\t-\t-\t-\t-\t-\tUYGULAMA ÇALIŞMIYOR\n" "$now" >> "$LOG"
        echo "$now  ⚠️  uygulama çalışmıyor"
    else
        read -r cpu rss <<< "$(ps -p "$pid" -o %cpu=,rss= | awk '{print $1, $2}')"
        mem=$(awk -v r="$rss" 'BEGIN{printf "%.1f", r/1024}')
        threads=$(ps -M "$pid" 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
        handles=$(lsof -p "$pid" 2>/dev/null | wc -l | tr -d ' ')
        taps=$(status_field kuruluTap)
        callbacks=$(status_field cagri)
        crashes=$(ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -ci "shutup")
        drops=$(status_field sesKesilmesi)
        if [ -n "${prev_drops:-}" ] && [ "${drops:-0}" -gt "$((prev_drops + 5))" ]; then
            note="${note}SES KESİLMESİ ARTIYOR ($prev_drops→$drops); "
        fi
        prev_drops="$drops"

        [ -z "$first_rss" ] && first_rss="$mem"
        [ -z "$first_threads" ] && first_threads="$threads"

        # Bellek ilk ölçümün iki katını aştıysa sızıntı şüphesi
        awk -v a="$mem" -v b="$first_rss" 'BEGIN{exit !(b>0 && a > b*2)}' && note="${note}BELLEK x2; "
        # İş parçacıkları sürekli artıyorsa takılan kurulum iş parçacıkları birikiyor olabilir
        [ "$threads" -gt $((first_threads + 10)) ] && note="${note}THREAD +10; "
        # Ses yolu açıkken IOProc ilerlemiyorsa yol sessizce durmuş demektir.
        # Uygulama yeniden başladıysa sayaç sıfırlanır; o yüzden aynı pid şartı aranıyor.
        if [ -n "${prev_callbacks:-}" ] && [ "${prev_pid:-}" = "$pid" ] \
           && [ "${taps:-0}" -gt 0 ] && [ "${callbacks:-0}" = "$prev_callbacks" ]; then
            note="${note}SES YOLU DURMUŞ; "
        fi
        # Ayar varken tap yoksa susturma uygulanmıyordur
        [ "${taps:-0}" = "0" ] && [ -n "$("$SHUTUP" status 2>/dev/null | grep -A2 kisilmis | grep ':')" ] && note="${note}AYAR VAR TAP YOK; "
        [ "$crashes" -gt "$crash_base" ] && note="${note}YENİ ÇÖKME; "

        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$now" "$pid" "$cpu" "$mem" "$threads" "$handles" "${taps:-?}" "${callbacks:-?}" "${drops:-?}" "$crashes" "${note:-ok}" >> "$LOG"
        if [ -n "$note" ]; then
            echo "$now  ⚠️  $note(bellek ${mem}MB, thread $threads, tap ${taps:-?})"
        else
            echo "$now  ok   bellek ${mem}MB · thread $threads · tanıtıcı $handles · tap ${taps:-?} · cpu ${cpu}%"
        fi
        prev_callbacks="$callbacks"; prev_taps="$taps"; prev_pid="$pid"
    fi

    count=$((count + 1))
    [ "$SAMPLES" -gt 0 ] && [ "$count" -ge "$SAMPLES" ] && break
    sleep "$INTERVAL"
done

echo "--- özet ---"
awk -F'\t' 'NR>1 && $4 != "-" {if(min==""||$4<min)min=$4; if($4>max)max=$4; sum+=$4; n++}
     END{if(n) printf "bellek: ilk %s MB → son %s MB (en düşük %s, en yüksek %s)\n", first, last, min, max}
     NR>1 && $4 != "-" {if(first=="")first=$4; last=$4}' "$LOG"
grep -c "UYGULAMA ÇALIŞMIYOR" "$LOG" | xargs echo "uygulama kapalı bulunma sayısı:"
grep -v "ok$" "$LOG" | tail -n +2 | wc -l | xargs echo "işaretlenen örnek sayısı:"
