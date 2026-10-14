#!/bin/bash
# Sağlık günlüğünü her an özetler — ölçüm sürerken de, yarıda kesilmişse de.
#   ./tools/health-report.sh
set -u
LOG="$(cd "$(dirname "$0")/.." && pwd)/tools/health-log.tsv"
[ -f "$LOG" ] || { echo "günlük yok: $LOG"; exit 1; }

awk -F'\t' '
NR == 1 { next }
{
    total++
    if ($2 == "-") { down++; next }

    if (first_time == "") { first_time = $1 }
    last_time = $1

    # Sürüm/oturum değişimini pid üzerinden takip et: uygulama yeniden başladıysa
    # bellek ve sayaçlar sıfırlanır, aynı seride karşılaştırmak yanıltıcı olur.
    if ($2 != cur_pid) { cur_pid = $2; runs++; run_first_mem[runs] = $4; run_pid[runs] = $2; run_n[runs] = 0 }
    run_n[runs]++
    run_last_mem[runs] = $4
    if (run_max_mem[runs] == "" || $4 + 0 > run_max_mem[runs] + 0) run_max_mem[runs] = $4
    if (run_max_thread[runs] == "" || $5 + 0 > run_max_thread[runs] + 0) run_max_thread[runs] = $5
    # Günlük iki biçimde olabilir: eski sürümde "ses kesilmesi" sütunu yok.
    # Sütun sayısına bakarak eşle, yoksa yoklukla göster.
    last_thread = $5; last_handles = $6; last_taps = $7
    if (NF >= 11) { last_drop = $9; last_crash = $10 } else { last_drop = "(ölçülmedi)"; last_crash = $9 }

    if ($NF != "ok") { flagged++; flags[$NF]++ }
}
END {
    printf "örnek sayısı   : %d  (%s → %s)\n", total, first_time, last_time
    printf "uygulama kapalı: %d örnek\n", down + 0
    printf "oturum sayısı  : %d  (uygulama bu kadar kez yeniden başlamış)\n\n", runs
    for (i = 1; i <= runs; i++) {
        printf "  oturum %d (pid %s, %d örnek): bellek %s → %s MB (tepe %s) · thread tepe %s\n",
               i, run_pid[i], run_n[i], run_first_mem[i], run_last_mem[i], run_max_mem[i], run_max_thread[i]
    }
    printf "\nson durum      : thread %s · tanıtıcı %s · ses yolu %s · ses kesilmesi %s · çökme %s\n",
           last_thread, last_handles, last_taps, last_drop, last_crash
    printf "işaretli örnek : %d\n", flagged + 0
    for (f in flags) printf "   • %s → %d kez\n", f, flags[f]
    print ""
    if (flagged + 0 == 0 && down + 0 == 0) print "değerlendirme  : sapma yok"
    else print "değerlendirme  : yukarıdaki işaretlere bak"
}' "$LOG"
