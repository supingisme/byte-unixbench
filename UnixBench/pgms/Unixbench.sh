#!/system/bin/sh
cat /data/pgms/unixbench.logo
Time=$(date '+%Y-%m-%d')
CPUNums=$(cat /proc/cpuinfo |grep "processor" |wc -l)
DeviceName=$(getprop ro.product.device)
ToolDir="/data/pgms"
TopDir="/data/pgms"
TmpPath="$TopDir/tmp"

if [ ! -d "$TopDir" ]; then
  mkdir $TopDir
fi

if [ ! -d "$TmpPath" ]; then
  mkdir $TmpPath
fi

FileCnt=1

while [ -d "$TopDir/$DeviceName-$Time-$FileCnt" ]
do
    FileCnt=`expr $FileCnt + 1`
done

DataDir="$TopDir/$DeviceName-$Time-$FileCnt"
LogPath="$DataDir/log"
IndexPath="$DataDir/index"
ResultPath="$DataDir/result"

mkdir $DataDir

export  UB_BINDIR=$ToolDir

TestCase=(
# name                                  command                                         baseline    repeat
"Dhrystone 2 using register variables"  "$ToolDir/dhry2reg 10"                                   "116700"    "long"
"Double-Precision Whetstone"            "$ToolDir/whetstone-double"                              "55"        "long"
"Execl Throughput"                      "$ToolDir/execl 30"                             "43"        "short"
"File Copy 1024 bufsize 2000 maxblocks" "$ToolDir/fstime -c -t 30 -d $TmpPath -b 1024 -m 2000"   "3960"      "short"
"File Copy 256 bufsize 500 maxblocks"   "$ToolDir/fstime -c -t 30 -d $TmpPath -b 256 -m 500"     "1655"      "short"
"File Copy 4096 bufsize 8000 maxblocks" "$ToolDir/fstime -c -t 30 -d $TmpPath -b 4096 -m 8000"   "5800"      "short"
"Pipe Throughput"                       "$ToolDir/pipe 10"                                       "12440"     "long"
"Pipe-based Context Switching"          "$ToolDir/context1 10"                                   "4000"      "long"
"Process Creation"                      "$ToolDir/spawn 30"                                      "126"       "short"
"Shell Scripts (1 concurrent)"          "$ToolDir/looper 60 $ToolDir/multi.sh 1"                 "42"        "short"
"Shell Scripts (8 concurrent)"          "$ToolDir/looper 60 $ToolDir/multi.sh 8"                 "6"         "short"
"System Call Overhead"                  "$ToolDir/syscall 10"                                    "15000"     "long"
)

CaseNums=`expr ${#TestCase[@]} / 4`

LongIterCount=10
ShortIterCount=3

ret=
CmdPID=()

function RunCmdOnce()
{
    { time -p $1 ; } 1>/dev/null 2>$IndexPath &
    pid=$!
    wait $pid
    
    flag=""    
    for output in `cat $IndexPath`
    do
        if [ "${output:0:5}" = "COUNT" ]; then
            arr=(${output//|/ })
            echo "COUNT0: ${arr[1]}" >> $LogPath
            echo "COUNT1: ${arr[2]}" >> $LogPath
            echo "COUNT2: ${arr[3]}" >> $LogPath
        fi
        
        if [ "$flag" = "real" ]; then
            elapsed=$output
            echo "elapsed: $elapsed" >> $LogPath
            echo "" >> $LogPath
            flag=""
        fi
        
        if [ "$output" = "real" ]; then
            flag="real"
        fi
    done
    
    ret="${arr[1]}|${arr[2]}|$elapsed"
    
    rm $IndexPath
}

function RunCmdPercpu()
{
    for i in $(seq 1 $CPUNums)
    do
        { time -p $1 ; } 1>/dev/null 2>$IndexPath$i &
        CmdPID[$i]=$!
    done

    for pid in ${CmdPID[@]}
    do
        wait $pid
    done
    
    sum=0
    totaltime=0
    for i in $(seq 1 $CPUNums)
    do
        flag=""
        for output in `cat $IndexPath$i`
        do
            if [ "${output:0:5}" = "COUNT" ]; then
                arr=(${output//|/ })
                echo "COUNT0: ${arr[1]}" >> $LogPath
                echo "COUNT1: ${arr[2]}" >> $LogPath
                echo "COUNT2: ${arr[3]}" >> $LogPath
                sum=$(echo "$sum ${arr[1]}" | awk '{print ($1+$2)}')
            fi
            
            if [ "$flag" = "real" ]; then
                elapsed=$output
                echo "elapsed: $elapsed" >> $LogPath
                echo "" >> $LogPath
                totaltime=$(echo "$totaltime $elapsed" | awk '{print ($1+$2)}')
                flag=""
            fi
            
            if [ "$output" = "real" ]; then
                flag="real"
            fi    
        done
    done
    elapsed=$(echo "$totaltime $CPUNums" | awk '{print ($1/$2)}')
    
    ret="$sum|${arr[2]}|$elapsed"
    
    for i in $(seq 1 $CPUNums)
    do
        rm $IndexPath$i
    done
}

function RunAllTests()
{
    Type=$1
    echo "---------------------------------------------------------------------------" >> $ResultPath
    echo "Benchmark Run: $(date '+%Y-%m-%d %H:%M:%S')" >> $ResultPath
    if [ "$Type" = "Single" ]; then
        echo "running 1 parallel copy of tests" >> $ResultPath
    else
        echo "running $CPUNums parallel copy of tests" >> $ResultPath
    fi
    printf "%-40s%10s%15s%10s\n" "System Benchmarks Index Values" "Baseline" "Result" "Score" >> $ResultPath
    
    ScoreSum=0
    for i in $(seq 0 `expr $CaseNums - 1`)
    do
        Name=${TestCase[`expr $i \* 4`]}
        Cmd=${TestCase[`expr $i \* 4 + 1`]}
        Base=${TestCase[`expr $i \* 4 + 2`]}
        Repeat=${TestCase[`expr $i \* 4 + 3`]}
        
        echo "########################################################" >> $LogPath
        echo "$Name" >> $LogPath
        
        if [ "$Repeat" = "long" ]; then
            RepeatCnt=$LongIterCount
        else
            RepeatCnt=$ShortIterCount
        fi
        
        if [ -n "$Name" ]; then
            echo "$Name"
            
            Ret=()
            for j in $(seq 1 $RepeatCnt)
            do
                if [ "$Type" = "Single" ]; then
                    RunCmdOnce "$Cmd"
                else
                    RunCmdPercpu "$Cmd"
                fi
                
                Ret[`expr $j - 1`]=$ret
                
                echo "#### Pass $j" >> $LogPath
            done
            
            Ret=( $(
                for el in "${Ret[@]}"
                do
                    echo "$el"
                done | sort -g) )

            Ndump=`expr $RepeatCnt / 3`
            
            Sum=0
            for j in $(seq 1 $RepeatCnt)
            do
                arr=(${Ret[`expr $j - 1`]//|/ })
                
                if [ $j -le $Ndump ]; then
                    echo "*Dump result: ${arr[0]}" >> $LogPath
                else
                    echo "Count result: ${arr[0]}" >> $LogPath
                    
                    if [ ${arr[1]} -gt 0 ]; then
                        Sum=$(echo "$Sum ${arr[*]}" | awk '{print $1+log($2/($4/$3))}')
                    else
                        Sum=$(echo "$Sum ${arr[0]}" | awk '{print $1+log($2)}')
                    fi
                fi
            done
            
            Average=$(echo "$Sum $RepeatCnt $Ndump" | awk '{print($1/($2-$3))}')
            Result=$(echo "$Average" | awk '{print exp($0)}')
            Score=$(echo "$Result $Base" | awk '{print ($1/$2*10)}')
            Tmp=$(echo $Score | awk '{print log($0)}')
            ScoreSum=$(echo "$ScoreSum $Tmp" | awk '{print($1+$2)}')
            
            printf ">>>> score: %f\n" "$Score" >> $LogPath
            printf ">>>> iterations: %d\n\n" `expr $RepeatCnt - $Ndump` >> $LogPath
            echo "Scores : $Score"
            printf "%-40s%10.1f%15.1f%10.1f\n" "$Name" "$Base" "$Result" "$Score" >> $ResultPath
        fi
    done
    
    ScoreSum=$(echo "$ScoreSum $CaseNums" | awk '{print($1/$2)}')
    ScoreSum=$(echo "$ScoreSum" | awk '{print exp($0)}')
    printf "%75s\n" "===================================" >> $ResultPath
    printf "%-40s%35.1f\n" "System Benchmarks Index Score" "$ScoreSum" >> $ResultPath
    echo "Benchmark End: $(date '+%Y-%m-%d %H:%M:%S')" >> $ResultPath
    printf "ScoreSum : %.1f\n" "$ScoreSum"
}

# single-processing run
echo "Benchmark Run: $(date '+%Y-%m-%d %H:%M:%S') -- 1 copy" >> $LogPath
RunAllTests "Single"
echo "########################################################" >> $LogPath
echo "Benchmark End: $(date '+%Y-%m-%d %H:%M:%S')" >> $LogPath
echo "" >> $LogPath
echo "" >> $LogPath

# multi-processing run
echo "Benchmark Run: $(date '+%Y-%m-%d %H:%M:%S') -- $CPUNums copy" >> $LogPath
RunAllTests "Multiple"
echo "########################################################" >> $LogPath
echo "Benchmark End: $(date '+%Y-%m-%d %H:%M:%S')" >> $LogPath
