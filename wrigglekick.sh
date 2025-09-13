#!/bin/bash

declare -a fileContentCache=()
declare cachedFileName=""
declare cacheValid=false

#エディタ、ビューワーの指定
selected_editor='selected_editor'
                #^^^^^^^^^^^^^^^ここにお好みのエディター呼び出しコマンドを設定してください
selected_viewer='selected_viewer'
                #^^^^^^^^^^^^^^^ここにお好みのビューワー呼び出しコマンドを設定してください

: "外部プロセス最適化ユーティリティ" && {
  function extractField {
    local input="${1}"
    local fieldNum="${2}"
    local IFS=$'\t'
    local -a fields=($input)
    echo "${fields[$((fieldNum-1))]}"
  }

function arrayContains {
    local target="${1}"
    shift
    local element
    for element in "$@"; do
      [[ "${element}" == "${target}" ]] && return 0
    done
    return 1
  }

  function countNonDotChars {
    local input="${1}"
    local cleaned="${input//[^$'\t']*$'\t'/}"
    cleaned="${cleaned//$'\n'/}"
    echo "${#cleaned}"
  }
}

: "ファイルキャッシュ系" && {
  function loadFileCache {
    local targetFile="${1}"
    if [[ "${cachedFileName}" != "${targetFile}" ]] || [[ "${cacheValid}" != true ]]; then
      readarray -t fileContentCache < "${targetFile}"
      cachedFileName="${targetFile}"
      cacheValid=true
    fi
  }

  function invalidateCache {
    cacheValid=false
  }

  function getCachedLines {
    local startLine="${1}"
    local endLine="${2}"
    local i
    for i in $(seq $((startLine-1)) $((endLine-1))); do
      if [[ ${i} -lt ${#fileContentCache[@]} ]]; then
        echo "${fileContentCache[${i}]}"
      fi
    done
  }

  function getCachedLineCount {
    echo "${#fileContentCache[@]}"
  }
}

: "ヘルプ表示" && {
  ##############################################################################
  # 引数:なし
  ##############################################################################
  function displayHelp {
    echo '■Simple Outliner'
    echo '>help'
    echo '　引数1:対象File'
    echo '　引数2:動作指定'
    echo '　　　　　t.....ツリービュー(省略可)'
    echo '　　　　　tl....行番号付きツリービュー'
    echo '　　　　　tla...行番号範囲深さ付きツリービュー'
    echo '　　　　　f.....フォーカスビュー'
    echo '　　　　　fl....行番号付きフォーカスビュー'
    echo '　　　　　fla...行番号範囲深さ付きフォーカスビュー'
    echo '　　　　　v.....対象ノードの閲覧'
    echo '　　　　　gv....対象ノードの配下ノードを横断的に閲覧'
    echo '　　　　　e.....対象ノードの編集'
    echo '　　　　　d.....対象ノードの削除'
    echo '　　　　　i.....対象ノードの下に新規ノード挿入。追加引数としてノード名'
    echo '　　　　　ie....対象ノードの下に新規ノード挿入、即編集モードへ。追加引数としてノード名'
    echo '　　　　　mu....対象ノードひとつを上へ移動'
    echo '　　　　　md....対象ノードひとつを下へ移動'
    echo '　　　　　ml....対象ノードひとつを左へ移動(浅くする)'
    echo '　　　　　mr....対象ノードひとつを右へ移動(深くする)'
    echo '　　　　　gmu...自分の配下ノードを引き連れて上へ移動'
    echo '　　　　　gmd...自分の配下ノードを引き連れて下へ移動'
    echo '　　　　　gml...自分の配下ノードを引き連れて左へ移動(浅くする)'
    echo '　　　　　gmr...自分の配下ノードを引き連れて右へ移動(深くする)'
    echo '　　　　　j.....指定ノードを、下のノードと結合'
    echo '　　　　　gj....自分の配下ノードを、自分に統合'
    echo '　　　　　c.....指定ノードの済/未マークを切り替える'
    echo '　　　　　gc....自分の配下ノードを含んだ文字数を通知する'
    echo '　　　　　s.....指定ノードに表示シンボルを設定する。追加引数でシンボルを指定(1文字)'
    echo '　　　　　o.....自分の配下ノードを含んだ範囲を別ファイル出力する。追加引数で出力ファイル名'
    echo '　　　　　数字...対象ノードを編集(eと引数3を省略)'
    echo '　引数3:動作対象ノード番号'
    echo '　引数4:動作指定ごとに必要なオプション'
  }
}

: "ノード検索最適化ユーティリティ" && {
  ##############################################################################
  ##############################################################################
  declare -A nodesByDepth
  declare -A nodeGroupStart
  declare -A nodeGroupEnd
  declare -A nextSiblingNode
  declare -A prevSiblingNode
  
  function buildNodeIndices {
    unset nodesByDepth nodeGroupStart nodeGroupEnd nextSiblingNode prevSiblingNode
    declare -gA nodesByDepth nodeGroupStart nodeGroupEnd nextSiblingNode prevSiblingNode
    
    for i in $(seq 1 ${maxNodeCnt}); do
      local depth="${nodeDepths[$((i-1))]}"
      if [[ -z "${nodesByDepth[$depth]}" ]]; then
        nodesByDepth[$depth]="$i"
      else
        nodesByDepth[$depth]="${nodesByDepth[$depth]} $i"
      fi
    done
    
    for i in $(seq 1 ${maxNodeCnt}); do
      local currentDepth="${nodeDepths[$((i-1))]}"
      local groupStart="$i"
      local groupEnd="$maxNodeCnt"
      
      for j in $(seq $((i + 1)) ${maxNodeCnt}); do
        local checkDepth="${nodeDepths[$((j-1))]}"
        if [[ $checkDepth -le $currentDepth ]]; then
          groupEnd=$((j - 1))
          break
        fi
      done
      
      nodeGroupStart[$i]="$groupStart"
      nodeGroupEnd[$i]="$groupEnd"
      
      for j in $(seq $((groupEnd + 1)) ${maxNodeCnt}); do
        local siblingDepth="${nodeDepths[$((j-1))]}"
        if [[ $siblingDepth -eq $currentDepth ]]; then
          nextSiblingNode[$i]="$j"
          prevSiblingNode[$j]="$i"
          break
        elif [[ $siblingDepth -lt $currentDepth ]]; then
          break
        fi
      done
    done
  }
}

: "メモリベースファイル操作ユーティリティ" && {
  ##############################################################################
  ##############################################################################
  
  function getFileLines {
    local startLine="${1}"
    local endLine="${2}"
    local targetFile="${3:-$inputFile}"
    
    if [[ -z "$startLine" ]] || [[ "$startLine" -eq 0 ]]; then
      startLine=1
    fi
    
    if [[ -z "$endLine" ]] || [[ "$endLine" -eq 0 ]]; then
      endLine=$(wc -l < "$targetFile")
    fi
    
    sed -n "${startLine},${endLine}p" "$targetFile"
  }
  
  function writeLinesToVar {
    local varName="${1}"
    local startLine="${2}"
    local endLine="${3}"
    local targetFile="${4:-$inputFile}"
    
    local content
    content=$(getFileLines "$startLine" "$endLine" "$targetFile")
    printf -v "$varName" '%s' "$content"
  }
  
  function createTempFileForEditor {
    local content="${1}"
    local tempFile="${2}"
    
    printf '%s\n' "$content" > "$tempFile"
  }
}
: "ノード検出" && {
  ##############################################################################
  # グローバル配列
  ##############################################################################
  declare -a nodeStartLines
  declare -a nodeEndLines
  declare -a nodeDepths
  declare -a nodeTitles
  declare -a nodeProgress
  declare -a nodeSymbol
  declare -a nodeCharCount

  ##############################################################################
  # ノード検出
  # 入力ファイルのノード構成を検出してグローバル設定する
  # 引数:なし(グローバル変数のみ参照)
  # グローバル変数設定:最大ノード数(maxNodeCnt)、各種配列
  ##############################################################################
  function detectNode {

    local entry
    local startLine
    local content      
    local endLine
    local title
    local progress
    local symbol
    local depth
    local nextEntry
    local nextStartLine
    
    loadFileCache "${inputFile}"
    
    #readarray -t indexlist < <(grep -nP '^\.+\t.+' ${inputFile})
    readarray -t indexlist < <(printf '%s\n' "${fileContentCache[@]}" | grep -nP '^\.+\t.+')
    
    readarray -t fileLines < "${inputFile}"

    maxNodeCnt="${#indexlist[@]}"

    #maxLineCnt="${#fileLines[@]}"
    maxLineCnt="$(getCachedLineCount)"
    
    nodeStartLines=()
    nodeEndLines=()
    nodeDepths=()
    nodeTitles=()
    nodeProgress=()
    nodeSymbols=()
    nodeCharCount=()

    for i in $(seq 1 ${maxNodeCnt}); do
      entry="${indexlist[$((i-1))]}"
      startLine="${entry%%:*}"
      content="${entry#*:}"      

      if [[ ${i} -ne ${maxNodeCnt} ]]; then
        nextEntry="${indexlist[${i}]}"
        nextStartLine="${nextEntry%%:*}"
        endLine=$((nextStartLine - 1))
      else
        endLine="${maxLineCnt}"
      fi
      
      depth="${content}"
      depth="${depth%%[^.]*}"
      depth="${#depth}"
      
      title="$(extractField "${content}" 2)"
      symbol="$(extractField "${content}" 4)"
      symbol="${symbol:0:1}" #1文字のみ
      
      nodeStartLines+=("${startLine}")
      nodeEndLines+=("${endLine}")
      nodeDepths+=("${depth}")
      nodeTitles+=("${title}")
      nodeSymbol+=("${symbol:=　}") #設定されていない場合には空白を一時的に設定

      progress="$(extractField "${content}" 3)"
      nodeProgress+=("${progress:=0}")

      #taかtlの場合以外はスキップする

      local countActionList=('tl' 'ta' 'fl' 'fa')
      if arrayContains "${action}" "${countActionList[@]}"; then
        #次の行がすぐに次のノードタイトル行(純粋なタイトル行)の場合は0文字
        if [[ ${startLine} -eq ${endLine} ]] ; then
          charCount=0
        else
          local contentLines=""
          for ((lineNum=startLine; lineNum<=endLine; lineNum++)); do
            local line="${fileLines[$((lineNum-1))]}"
            if [[ ! "${line}" =~ ^\. ]]; then
              contentLines+="${line}"
            fi
          done
          charCount="${#contentLines}"
        fi
        nodeCharCount+=("${charCount}")
      fi

    done
    
    buildNodeIndices
  }
}

: "シンボル系" && {
  ##############################################################################
  # 選択ノードの済マーク(☑️)と未済(⬜️)のマークを切り替える
  # 引数:なし(グローバルのみ)
  ##############################################################################
  function switchProgress {
    
    local presentProgress="${nodeProgress[$((indexNo-1))]:=0}"
    presentProgress="${presentProgress:0:1}" #不正な文字が入っていた場合に1文字に削る

    if [[ ${presentProgress} -eq 0 ]] ; then
      modifiyProgress=1
    else
      modifiyProgress=0
    fi

    local targetLineNo="${nodeStartLines[$((indexNo-1))]}"
    local presentTitlelineContent="$( getNodeTitlelineContent ${indexNo} )"

    local part_before="$(extractField "${presentTitlelineContent}" 1)$(printf '\t')$(extractField "${presentTitlelineContent}" 2)"
    # local part_progress="$(extractField "${presentTitlelineContent}" 3)"
    local part_after="$(extractField "${presentTitlelineContent}" 4)"

    modifiedTitlelineContent="$( echo -e "${part_before}\t${modifiyProgress}\t${part_after}" )"

    sed -i "${targetLineNo} c ${modifiedTitlelineContent}" "${inputFile}"
    invalidateCache

    bash "${0}" "${inputFile}" 'tl'
    exit 0
  }

  ##############################################################################
  # 選択ノードにシンボルを設定。指定シンボルを空にした場合は削除
  # 引数:なし(グローバルのみ)
  # 引数2:設定するシンボル(1文字のみ)
  ##############################################################################
  function setSymbol {

    local modifySymbol="${option:0:1}" #1文字のみ

    local targetLineNo="${nodeStartLines[$((${indexNo}-1))]}"

    local part_before="$( seq ${nodeDepths[$((indexNo-1))]} | while read -r line; do printf '.'; done )"
    part_before="${part_before}\t${nodeTitles[$((indexNo-1))]}\t${nodeProgress[$((indexNo-1))]}"

    local modifiedTitlelineContent="$( echo -e "${part_before}\t${modifySymbol}" )"

    sed -i "${targetLineNo} c ${modifiedTitlelineContent}" "${inputFile}"
    invalidateCache

    bash "${0}" "${inputFile}" 't'
    exit 0
  }
}

: "深さ取得" && {
  ##############################################################################
  # 深さ取得
  # 対象ノードの深さを取得する
  # 引数1:対象ノード番号
  # 標準出力:対象ノードの深さ
  ##############################################################################
  function getDepth {
    
    local selectNode="${1}"
    echo "${nodeDepths[$((selectNode-1))]}"

  }
}

: "ノード行範囲取得" && {
  ##############################################################################
  # 行番号取得
  # ノード番号から、対象ノードの開始行数と終了行数を取得する
  # 引数1:対象ノード番号
  # 引数2:出力する行の種類　1:開始行番号を出力/9:終了行番号を出力
  # 標準出力:引数2が1……開始行番号
  #               2……終了行番号
  #               なし、もしくはそれ以外……開始行番号 終了行番号
  ##############################################################################
  function getLineNo {
    local selectNodeNo="${1}"
    local mode="${2}"
    local startLine="${nodeStartLines[$((selectNodeNo-1))]}"
    local endLine="${nodeEndLines[$((selectNodeNo-1))]}"

    case "${mode}" in
      '') echo "${startLine} ${endLine}" ;;
      1) echo  "${startLine}" ;;
      9) echo  "${endLine}" ;;
      *) echo  "${startLine} ${endLine}" ;;
    esac

  }
}

: "タイトル取得系" && {
  ##############################################################################
  # ノードタイトル取得(タイトル部分のみ)
  # 対象ノードのタイトルを取得する
  # 引数1:対象ノード番号
  # 戻り値:なし
  # 標準出力:対象ノードのタイトル
  ##############################################################################
  function getNodeTitle {
    
    local selectNode="${1}"
    echo "${nodeTitles[$((selectNode-1))]}"

  }
  ##############################################################################
  # ノードタイトル取得(タイトル行全体)
  # 対象ノードのタイトル行全体を取得する
  # 引数:なし(グローバルのみ)
  # 戻り値:なし
  # 標準出力:対象ノードのタイトル行全体
  ##############################################################################
  function getNodeTitlelineContent {
    local selectNodeLineNo="${nodeStartLines[ $(( ${1}-1 )) ]}"

    echo "${fileLines[$((selectNodeLineNo-1))]}"

  }
}

: "グループ範囲取得系" && {
  ##############################################################################
  # 選択ノードの所属するグループの範囲(ノード番号)を取得する
  # 引数1:対象ノード番号
  # 引数2:出力する行の種類　1:開始行番号を出力/9:終了行番号を出力
  # 標準出力:引数2が1……開始行番号
  #               2……終了行番号
  #               なし、もしくはそれ以外……開始行番号 終了行番号
  ##############################################################################
  function getNodeNoInGroup {
    local selectNodeNo="${1}"
    local mode="${2}"
    
    local startNodeSelectGroup="${nodeGroupStart[$selectNodeNo]}"
    local endNodeSelectGroup="${nodeGroupEnd[$selectNodeNo]}"
    
    case "${mode}" in
      '') echo "${startNodeSelectGroup} ${endNodeSelectGroup}" ;;
      1) echo  "${startNodeSelectGroup}" ;;
      9) echo  "${endNodeSelectGroup}" ;;
      *) echo  "${startNodeSelectGroup} ${endNodeSelectGroup}" ;;
    esac
  }

  ##############################################################################
  # 選択ノードの所属するグループの一つ上/下のグループの範囲(ノード番号)を取得する
  # 引数1:対象ノード番号
  # 引数2:方向　u:上/d:下
  # 引数3:出力する行の種類　1:開始行番号を出力/9:終了行番号を出力
  # 戻り値:（グループがないとき）e
  # 標準出力:引数2が1……開始行番号
  #               2……終了行番号
  #               なし、もしくはそれ以外……開始行番号 終了行番号
  ##############################################################################
  function getTargetNodeNoInGroup {
    local selectNodeNo="${1}"
    local direction="${2}"
    local mode="${3}"
    local selectNodeDepth="${nodeDepths[$((selectNodeNo-1))]}"
    
    local returnNodeNo=""
    
    case "${direction}" in
      [uU]) returnNodeNo="${prevSiblingNode[$selectNodeNo]}" ;;
      [dD]) returnNodeNo="${nextSiblingNode[$selectNodeNo]}" ;;
      *)    returnNodeNo="${nextSiblingNode[$selectNodeNo]}" ;;
    esac
    
    if [[ -z "$returnNodeNo" ]]; then
      exit 100
    fi
    
    local TargetGroupFromTo="$(getNodeNoInGroup ${returnNodeNo} '' )"
    local startnodeTargetGroup="$( echo ${TargetGroupFromTo} | cut -d ' ' -f 1 )"
    local endnodeTargetGroup="$(   echo ${TargetGroupFromTo} | cut -d ' ' -f 2 )"

    case "${mode}" in
      '') echo "${startnodeTargetGroup} ${endnodeTargetGroup}" ;;
      1) echo  "${startnodeTargetGroup}" ;;
      9) echo  "${endnodeTargetGroup}" ;;
      *) echo  "${startnodeTargetGroup} ${endnodeTargetGroup}" ;;
    esac
  }
}

: "配下ノード閲覧コマンド" && {
  ##############################################################################
  # 選択ノードから、下方向に選択ノードよりも深さが深い限り続くノード範囲を対象に、閲覧する
  # 引数:なし(グローバルのみ)
  ##############################################################################
  function groupView {

    local tgtGroup="$( getNodeNoInGroup ${indexNo} '' )"
    local startLineSelectGroup="$( getLineNo $( echo ${tgtGroup} | cut -d ' ' -f 1 ) 1 )"
    local endLineSelectGroup="$( getLineNo $( echo ${tgtGroup} | cut -d ' ' -f 2 ) 9 )"

    writeLinesToVar "tmpContentTarget" "${startLineSelectGroup}" "${endLineSelectGroup}"
    createTempFileForEditor "$tmpContentTarget" "$tmpfileTarget"
    "${selected_viewer}" "${tmpfileTarget}"
    bash "${0}" "${inputFile}" 't'
    exit 0
  }
}

: "範囲文字数カウント表示" && {
  ##############################################################################
  # 開始行数から数量行数までの、空行とノードタイトル行を除外した文字数をカウントする
  # 引数1:開始行数
  # 引数2:終了行数
  # 戻り値:なし
  # 標準出力:文字数
  ##############################################################################
  function groupCharCount {

    local lineStart="${1}"
    local lineEnd="${2}"
    
    local contentLines=""
    for ((lineNum=lineStart; lineNum<=lineEnd; lineNum++)); do
      local line="${fileLines[$((lineNum-1))]}"
      if [[ ! "${line}" =~ ^\. ]]; then
        contentLines+="${line}"
      fi
    done
    echo "${#contentLines}"

  }
  
  ##############################################################################
  # 選択ノードから、下方向に選択ノードよりも深さが深い限り続くノード範囲を対象に、文字数をカウントして表示する。
  # 空行と、ノードタイトル行は除外する。
  # 引数:なし(グローバルのみ)
  # 標準出力:文字数表示(アナウンス)
  ##############################################################################
  function dispGroupCharCount {

    local tgtGroupStart="$( getLineNo $( getNodeNoInGroup ${indexNo} 1 ) 1 )"
    local tgtGroupEnd="$( getLineNo $( getNodeNoInGroup ${indexNo} 9 ) 9 )"

    count="$( groupCharCount ${tgtGroupStart} ${tgtGroupEnd} )"

    printf "ノード番号%dの配下の文字数合計 : %d\n" "${indexNo}" "${count}"
    printf "※ %d行目から%d行目。空行とノードタイトル行の文字含まず。\n" "${tgtGroupStart}" "${tgtGroupEnd}"
  }
}

: "ツリー表示系" && {
  ##############################################################################
  # ツリー表示する
  # t:通常ツリー
  # tl:開始行番号付きツリー表示
  # ta:開始終了行番号深さ付きツリー表示
  # 先頭から末尾を指定してツリービューを呼び出すラッパー
  ##############################################################################
  function displayTree {
    tree 1 "${maxNodeCnt}" "${allCharCount}"
  }

  ##############################################################################
  # 対象グループをフォーカス表示する
  # f:通常フォーカス表示
  # fl:開始行番号付きフォーカス表示
  # fa:開始終了行番号深さ付きフォーカス表示
  # グループ(開始ノードと終了ノード)を指定してツリービューを呼び出すラッパー
  ##############################################################################
  function focusMode {

    local SelectGroupNodeFromTo="$(getNodeNoInGroup ${indexNo} '' )"
    local startNodeSelectGroup="$( echo ${SelectGroupNodeFromTo} | cut -d ' ' -f 1 )"
    local endNodeSelectGroup="$( echo ${SelectGroupNodeFromTo} | cut -d ' ' -f 2 )"
    local focusCount="$( groupCharCount $( getLineNo ${startNodeSelectGroup} 1 ) $( getLineNo ${endNodeSelectGroup} 9 ) )"
    
    tree "${startNodeSelectGroup}" "${endNodeSelectGroup}" "${focusCount}"

  }

  ##############################################################################
  # ツリー表示する
  # t:通常ツリー
  # tl:開始行番号付きツリー表示
  # ta:開始終了行番号深さ付きツリー表示
  # 引数1: 開始グループ番号
  # 引数2: 終了グループ番号
  ##############################################################################
  function tree {
    local startNodeSelectGroup="${1}"
    local endNodeSelectGroup="${2}"
    local allCharCount="${3}"

    printf "【$(basename ${inputFile})】合計${allCharCount}文字"
    
    case "${char1}" in
      't')  echo '';;
      'f')  echo " ★ フォーカス表示中";;
      *)    echo '';;
    esac
    case "${char2}" in
      '') echo '節   アウトライン'
          echo '====+============'
          ;;
      'l')  echo '節   行番号   字数   済 アウトライン'
            echo '====+========+======+==+============'
            ;;
      'a')  echo '節   行番号            深  字数   済 アウトライン'
            echo '====+========+========+===+======+==+============'
            ;;
      *)    ;;
    esac

    seq "${startNodeSelectGroup}" "${endNodeSelectGroup}" | {
      while read -r cnt ; do
        startLine="$( getLineNo ${cnt} 1 )"
        endLine="$(   getLineNo ${cnt} 9 )"
        depth="$( getDepth ${cnt} )"

        count="${nodeCharCount[$((cnt-1))]}"
        progress="${nodeProgress[$((cnt-1))]:=0}"

        if [[ ${progress} -eq 1 ]] ; then
          progress='☑️ '
        else
          progress='⬜️'
        fi

        symbols="${nodeSymbol[$((cnt-1))]}"

        printf "%04d" "${cnt}"

        case "${char2}" in
          '')  :
                ;;
          'l') printf " %08d %06d %s" "${startLine}" "${count}" "${progress}"
                ;;
          'a') printf " %08d~%08d %03d %06d %s" "${startLine}" "${endLine}" "${depth}" "${count}" "${progress}"
                ;;
          *)    ;;
        esac

        seq ${depth} | while read -r line; do printf ' '; done
        
        case "${depth}" in
          '1') printf '📚️ '
              ;;
          '2') printf '└📗 '
              ;;
          [34]) printf '└📖 '
                ;;
          [567]) printf '└📄 '
                ;;
          [89]) printf '└🏷️ '
                ;;
          '10')  printf '└🗨️ '
                ;;        
          *) printf '└🗨️ '
            ;;
        esac 

        printf "%s " "${symbols}"

        echo "$( getNodeTitle ${cnt} )"

      done

    }

    echo '❓️引数なしでhelp参照'
    exit 0
   
  }
}

: "ノード出力系コマンド" && {
  ##############################################################################
  # 配下ノードを含んだ範囲を別ファイルに出力する
  # 引数1: 出力ファイルパス(ファイル名含)
  # ノード指定と入力ファイルはグローバルから取得
  ##############################################################################
  function outputGroup {

    local outputFile="${1}"


    if [[ -z "${outputFile/ /}" ]] ; then
      local nodeTitles="${nodeTitles[$((${indexNo}-1))]}"
      outputFile="./${nodeTitles}.txt"
      echo "出力ファイル名の指定がなかったため、ノード名を使用します。"
    fi

    if [[ -f "${outputFile}" ]] ; then
      printf "出力先に既に同名のファイルがあります。上書きしますか？ (y/n)\n>"
      read yn
      if [[ "${yn}" != 'y' ]] ; then
        echo "出力を中止しました。"
        exit 0
      fi
    fi

    local selectGroupFromTo="$( getNodeNoInGroup ${indexNo} '' )"
    local startLineSelectGroup="$( getLineNo $( echo ${selectGroupFromTo} | cut -d ' ' -f 1 ) 1 )"
    local endLineSelectGroup="$( getLineNo $( echo ${selectGroupFromTo} | cut -d ' ' -f 2 ) 9 )"

    sed -n "${startLineSelectGroup},${endLineSelectGroup}p" "${inputFile}" > "${outputFile}"
    
    echo "ノード範囲を出力しました: ${outputFile}"
    exit 0
  }
}

: "ノード削除・ノード編集・単一ノード閲覧コマンド" && {
  ##############################################################################
  # d:対象のノードを削除する
  # e:対象のノードを編集する
  # v:対象のノードを閲覧する
  ##############################################################################
  function singleNodeOperations {

    selectNodeLineFromTo="$( getLineNo ${indexNo} '' )"
    local selectNodeArray=($selectNodeLineFromTo)
    startLineSelectNode="${selectNodeArray[0]}"
    endLineSelectNode="${selectNodeArray[1]}"

    endLineHeader="$(( ${startLineSelectNode} -1 ))"
    startLineFooter="$(( ${endLineSelectNode} +1 ))"

    if [[ ${indexNo} -eq 1 ]]; then
      tmpContentHeader=""
    else
      writeLinesToVar "tmpContentHeader" "1" "${endLineHeader}"
    fi
    
    if [[ ${indexNo} -eq 1 ]] ; then
      writeLinesToVar "tmpContentSelect" "1" "${endLineSelectNode}"
    else
      if [[ ${indexNo} -eq ${maxNodeCnt} ]] ; then
        writeLinesToVar "tmpContentSelect" "${startLineSelectNode}" ""
      else
        writeLinesToVar "tmpContentSelect" "${startLineSelectNode}" "${endLineSelectNode}"
      fi
    fi
    
    if [[ ${indexNo} -eq ${maxNodeCnt} ]] ; then
      tmpContentFooter=""
    else
      writeLinesToVar "tmpContentFooter" "${startLineFooter}" ""
    fi

    case "${action}" in
      'e')  createTempFileForEditor "$tmpContentSelect" "$tmpfileSelect"
            "${selected_editor}" "${tmpfileSelect}"
            wait
            sed -i -e '$a\' "${tmpfileSelect}"
            tmpContentSelect=$(cat "$tmpfileSelect")
            printf '%s\n%s\n%s\n' "$tmpContentHeader" "$tmpContentSelect" "$tmpContentFooter" > "${inputFile}"
            ;;
      'd')  printf '%s\n%s\n' "$tmpContentHeader" "$tmpContentFooter" > "${inputFile}"
            ;;
      'v')  createTempFileForEditor "$tmpContentSelect" "$tmpfileSelect"
            "${selected_viewer}" "${tmpfileSelect}"
            ;;
      *)    echo '不正な引数です。'
            exit 9
            ;;
    esac

    bash "${0}" "${inputFile}" 't'
    exit 0
  }
}

: "ノード挿入コマンド" && {
  ##############################################################################
  # 対象のノードの下に新しいノードを挿入する
  # 引数:なし(グローバルのみ)
  ##############################################################################
  function insert {
    nlString="${option:-名称未設定}"
    endLinePreviousNode="$( getLineNo ${indexNo} 9 )"
    startLineNextNode="$(   getLineNo $(( ${indexNo} +1 )) 1 )"

    depth="$( getDepth ${indexNo} )"
    dots="$(seq ${depth} | while read -r line; do printf '.'; done)"

    tmpContentSelect="${dots}\t${nlString}"
    writeLinesToVar "tmpContentHeader" "1" "${endLinePreviousNode}"

    if [[ ${indexNo} -eq ${maxNodeCnt} ]] ;then
      printf '%s\n%s\n' "$tmpContentHeader" "$tmpContentSelect" > "${inputFile}"
    else
      writeLinesToVar "tmpContentFooter" "${startLineNextNode}" ""
      printf '%s\n%s\n%s\n' "$tmpContentHeader" "$tmpContentSelect" "$tmpContentFooter" > "${inputFile}"
    fi
  }


  ##############################################################################
  # 対象のノードの下に新しいノードを挿入する
  # 引数:なし(グローバルのみ)
  ##############################################################################
  function insertEdit {
    insert
    bash "${0}" "${inputFile}" 'e' "$((${indexNo} + 1))"
    exit 0
  }

  ##############################################################################
  # 対象のノードの下に新しいノードを挿入する
  # 引数:なし(グローバルのみ)
  ##############################################################################
  function insertNode {    
    insert
    bash "${0}" "${inputFile}" 't'
    exit 0
  }
}

: "単ノード深さ変更コマンド" && {
  ##############################################################################
  # 対象のノード一つだけの深さを変更する
  # 引数:なし(グローバルのみ)
  ##############################################################################
  function slideNode {

    tgtLine="$(getLineNo ${indexNo} 1 )"

    case "${char2}" in
      'l')  sed -i -e "$tgtLine s/^\.\./\./g" "${inputFile}"
            invalidateCache
            ;;
      'r')  sed -i -e "$tgtLine s/^/\./g" "${inputFile}"
            invalidateCache
            ;;
      *)    echo 'err'
            exit 9
            ;;
    esac

    bash "${0}" "${inputFile}" 'ta'
    exit 0

  }
}

: "単ノード上下交換コマンド" && {
  ##############################################################################
  # 対象のノード一つだけを上下に移動する(指定の方向のノードと入れ替える)
  # 引数:なし(グローバルのみ)
  ##############################################################################
  function swapNode {

    local indexTargetNode=''
    local indexNextNode=''
    local endLinePreviousNode=''
    local startLineTargetNode=''
    local endLineTargetNode=''
    local targetNodeLineFromTo=''

    local indexSelectNode="$(( ${indexNo} ))"
    local selectNodeLineFromTo="$( getLineNo ${indexSelectNode} '' )"
    local selectNodeArray=($selectNodeLineFromTo)
    local startLineSelectNode="${selectNodeArray[0]}"
    local endLineSelectNode="${selectNodeArray[1]}"

    case "${char2}" in
      'u')  indexTargetNode="$(( ${indexNo} -1 ))"
            #indexSelectNode="$(( ${indexNo}    ))"
            indexNextNode="$((   ${indexNo} +1 ))"

            endLinePreviousNode="$(( $( getLineNo ${indexTargetNode} 1 ) - 1 ))"

            targetNodeLineFromTo="$( getLineNo ${indexTargetNode} '' )"
            local targetNodeArray=($targetNodeLineFromTo)
            startLineTargetNode="${targetNodeArray[0]}"
            endLineTargetNode="${targetNodeArray[1]}"

            if [[ ${indexNo} -eq ${maxNodeCnt} ]] ; then
              startLineNextNode=''
            else
              startLineNextNode="$( getLineNo ${indexNextNode} 1 )"
            fi
            
            writeLinesToVar "tmpContentHeader" "1" "${endLinePreviousNode}"
            writeLinesToVar "tmpContentTarget" "${startLineTargetNode}" "${endLineTargetNode}"
            writeLinesToVar "tmpContentSelect" "${startLineSelectNode}" "${endLineSelectNode}"
            
            if [[ ! "${startLineNextNode}" = '' ]] ; then 
              writeLinesToVar "tmpContentFooter" "${startLineNextNode}" ""
            else
              tmpContentFooter=""
            fi
            
            tmpContent1="${tmpContentHeader}${tmpContentSelect:+$'\n'$tmpContentSelect}"
            tmpContent2="${tmpContentTarget}${tmpContentFooter:+$'\n'$tmpContentFooter}"
            
            printf '%s\n%s\n' "$tmpContent1" "$tmpContent2" > "${inputFile}"

            ;;

      'd')  indexPreviousNode="$(( ${indexNo} -1 ))"
            #indexSelectNode="$((   ${indexNo}    ))"
            indexTargetNode="$((   ${indexNo} +1 ))"
            indexNextNode="$((     ${indexNo} +2 ))"
            
            endLinePreviousNode="$( getLineNo ${indexPreviousNode} 9 )"

            targetNodeLineFromTo="$( getLineNo ${indexTargetNode} '' )"
            local targetNodeArray=($targetNodeLineFromTo)
            startLineTargetNode="${targetNodeArray[0]}"

            if [[ ${indexNo} -eq ${maxNodeCnt} ]] ; then

              #endLineTargetNode="${#fileLines[@]}"
              endLineTargetNode="$(getCachedLineCount)"

            else
              endLineTargetNode="${targetNodeArray[1]}"
              startLineNextNode="$( getLineNo ${indexNextNode}   1 )"
            fi
            if [[ ${indexNo} -eq 1 ]] ; then
              tmpContentHeader=""
            else
              writeLinesToVar "tmpContentHeader" "1" "${endLinePreviousNode}"
            fi
            writeLinesToVar "tmpContentTarget" "${startLineTargetNode}" "${endLineTargetNode}"
            writeLinesToVar "tmpContentSelect" "${startLineSelectNode}" "${endLineSelectNode}"
            if [[ ! ${startLineNextNode} = '' ]] ; then 
              writeLinesToVar "tmpContentFooter" "${startLineNextNode}" ""
            else
              tmpContentFooter=""
            fi
            
            tmpContent1="${tmpContentHeader}${tmpContentTarget:+$'\n'$tmpContentTarget}"
            tmpContent2="${tmpContentSelect}${tmpContentFooter:+$'\n'$tmpContentFooter}"
            
            printf '%s\n%s\n' "$tmpContent1" "$tmpContent2" > "${inputFile}"
            ;;

      *)    echo 'err'
            exit 9
            ;;
    esac

    bash "${0}" "${inputFile}" 't'
    exit 0
  }
}

: "配下ノード深さ変更コマンド" && {
  ##############################################################################
  # 対象のノードとその配下の深さを、一緒に変更する
  # 引数:なし(グローバルのみ)
  ##############################################################################
  function slideGroup {

    local SelectGroupNodeFromTo="$( getNodeNoInGroup ${indexNo} '' )"
    local selectGroupArray=($SelectGroupNodeFromTo)
    local startNodeSelectGroup="${selectGroupArray[0]}"
    local endNodeSelectGroup="${selectGroupArray[1]}"

    case "${char3}" in
      'l')  local startNode="${nodeGroupStart[$indexNo]}"
            local endNode="${nodeGroupEnd[$indexNo]}"
            for i in $(seq "${startNode}" "${endNode}") ; do
              tgtLine="$( getLineNo ${i} 1 )"
              sed -i -e "${tgtLine} s/^\.\./\./g" "${inputFile}"
            done
            invalidateCache
            ;;
      'r')  local startNode="${nodeGroupStart[$indexNo]}"
            local endNode="${nodeGroupEnd[$indexNo]}"
            for i in $(seq "${startNode}" "${endNode}") ; do
              tgtLine="$( getLineNo ${i} 1 )"
              sed -i -e "${tgtLine} s/^\./\.\./g" "${inputFile}"
            done
            invalidateCache
            ;;
      *)    echo 'err'
            read -s -n 1 c
            exit 9
            ;;
    esac

    bash "${0}" "${inputFile}" 'ta'
    exit 0

  }
}

: "配下ノード上下交換コマンド" && {
  ##############################################################################
  # 対象のノードとその配下と、対象ノードと同じ高さの上下ノードとその配下とを、同時に入れ替える
  # 引数:なし(グローバルのみ)
  ##############################################################################
  function swapGroup {

    local selectNodeDepth=0
    local depthCheck=0
    local direction="${char3}"

    local selectNodeLineFromTo=''
    local startLineSelectGroup=''
    local endLineSelectGroup=''

    local targetNodeLineFromTo=''
    local startLineTargetGroup=''
    local endLineTargetGroup=''

    : "選択グループ情報を取得" && {
      selectNodeLineFromTo="$( getNodeNoInGroup ${indexNo} '' )"
      local selectNodeArray=($selectNodeLineFromTo)
      startLineSelectGroup="$(getLineNo ${selectNodeArray[0]} 1 )"
      endLineSelectGroup="$(  getLineNo ${selectNodeArray[1]} 9 )"

    }

    : "移動先グループ情報を取得" && {
      #上移動の場合
      ##かつ対象ノードが一番上の場合
      targetNodeLineFromTo="$(getTargetNodeNoInGroup "${indexNo}" "${direction}" '' )" 
      if [[ "${?}" -ne 0 ]] ; then
        echo '交換移動可能なグループがありません'
        read -s -n 1 c
        bash "${0}" "${inputFile}" 't'
        exit 0
      else
        local targetNodeArray=($targetNodeLineFromTo)
        startLineTargetGroup="$(getLineNo ${targetNodeArray[0]} 1 )"
        endLineTargetGroup="$(  getLineNo ${targetNodeArray[1]} 9 )"
      fi
    }

    : "ヘッダ部分の情報を取得" && {
      # directionがu(上と交換)の場合:1行目〜「移動先グループの先頭ノードの先頭行の１行前(startLineTargetGroup-1)」
      # directionがd(下と交換)の場合:1行目〜「選択グループの先頭ノードの先頭行の1行前(startLineSelectGroup-1)
      
      if [[ ${startLineTargetGroup} -eq 1 ]] ; then
        startLineHeaderGroup=0
        endLineHeaderGroup=0
      else
        startLineHeaderGroup=1
        case "${direction}" in
          [uU]) endLineHeaderGroup="$(( ${startLineTargetGroup} -1 ))"
                ;;
          [dD]) endLineHeaderGroup="$(( ${startLineSelectGroup} -1 ))"
                ;;
          *)  echo 'err'
              ;;
        esac
      fi
    }

    : "フッタ部分の情報を取得" && {
      # directionがu(上と交換)の場合:「選択グループの末尾ノードの末尾行の1行後ろ(endLineSelectGroup+1)」〜最終行
      # directionがd(下と交換)の場合:「移動先グループの末尾ノードの末尾行の1行後ろ(endLineTargetGroup+1)」〜最終行

      if [[ ${endLineTargetGroup} -eq ${maxLineCnt} ]] ; then
        startLineFooterGroup="${maxLineCnt}"
        endLineFooterGroup="${maxLineCnt}"
      else
        case "${direction}" in
          [uU]) startLineFooterGroup="$(( ${endLineSelectGroup} +1 ))"
                ;;
          [dD]) startLineFooterGroup="$(( ${endLineTargetGroup} +1 ))"
                ;;
          *)  echo 'err'
              exit 9
              ;;
        esac
        endLineFooterGroup="${maxLineCnt}"
      fi
    }

   if [[ ${endLineHeaderGroup} -ne 0 ]] ; then
     getCachedLines "1" "${endLineHeaderGroup}" > "${tmpfileHeader}"
    else
      printf '' > "${tmpfileHeader}"
    fi

    writeLinesToVar "tmpContentTarget" "${startLineTargetGroup}" "${endLineTargetGroup}"
    writeLinesToVar "tmpContentSelect" "${startLineSelectGroup}" "${endLineSelectGroup}"

    if [[ ${startLineFooterGroup} -ne ${maxLineCnt} ]] ; then
      writeLinesToVar "tmpContentFooter" "${startLineFooterGroup}" ""
    else
      tmpContentFooter=""
    fi

    case "${direction}" in
      [uU]) tmpContent1="${tmpContentHeader}${tmpContentSelect:+$'\n'$tmpContentSelect}"
            tmpContent2="${tmpContentTarget}${tmpContentFooter:+$'\n'$tmpContentFooter}"
            ;;
      [dD]) tmpContent1="${tmpContentHeader}${tmpContentTarget:+$'\n'$tmpContentTarget}"
            tmpContent2="${tmpContentSelect}${tmpContentFooter:+$'\n'$tmpContentFooter}"
            ;;
      *)    echo 'err'
            read -s -n 1 c
            exit 9
            ;;
    esac

    printf '%s\n%s\n' "$tmpContent1" "$tmpContent2" > "${inputFile}"
    bash "${0}" "${inputFile}" 't'
    exit 0

  }
}

: "配下ノード削除コマンド" && {
  ##############################################################################
  # 対象のノードとその配下を削除する
  # 引数:なし(グローバルのみ)
  ##############################################################################
  function deleteGroup {

    local selectGroupNodeFromTo="$( getNodeNoInGroup ${indexNo} '' )"
    local startNodeSelectGroup="$( echo ${selectGroupNodeFromTo} | cut -d ' ' -f 1 )"
    local endNodeSelectGroup="$(   echo ${selectGroupNodeFromTo} | cut -d ' ' -f 2 )"

    local startLineSelectGroup="$( getLineNo ${startNodeSelectGroup} 1 )"
    local endLineSelectGroup="$(   getLineNo ${endNodeSelectGroup} 9 )"

    local endLineHeader="$(( ${startLineSelectGroup} - 1 ))"
    local startLineFooter="$(( ${endLineSelectGroup} + 1 ))"

    (
      if [[ ${endLineHeader} -eq 0 ]]; then
        printf '' > "${tmpfileHeader}"
      else
        getCachedLines "1" "${endLineHeader}" > "${tmpfileHeader}"
      fi
      wait
    )
    (
      if [[ ${startLineFooter} -gt ${maxLineCnt} ]] ; then
        printf '' > "${tmpfileFooter}"
      else
        getCachedLines "${startLineFooter}" "${maxLineCnt}" > "${tmpfileFooter}"
      fi
      wait
    )

    cat "${tmpfileHeader}" "${tmpfileFooter}" > "${inputFile}"
    invalidateCache

    bash "${0}" "${inputFile}" 't'
    exit 0
  }
}

: "ノード結合" && {
  ##############################################################################
  # ノード結合
  # 引数:なし(グローバルのみ)
  # 指定のノードに、指定のノードのひとつ下のノードを結合する。
  ##############################################################################
  function joinNode {

    local tgtLine="$( echo ${nodeStartLines[${indexNo}]} )"
    sed -i "${tgtLine}d" "${inputFile}"
    invalidateCache
    bash "${0}" "${inputFile}" 't'
    exit 0
  }

  ##############################################################################
  # 配下ノード結合
  # 引数:なし(グローバルのみ)
  # 指定のノードに、指定のノード配下のノードすべてを結合する
  ##############################################################################
  function joinGroup {

    local selectGroupNodeFromTo="$( getNodeNoInGroup ${indexNo} '' )"
    local startNodeSelectGroup="$( echo ${selectGroupNodeFromTo} | cut -d ' ' -f 1 )"
    local endNodeSelectGroup="$(   echo ${selectGroupNodeFromTo} | cut -d ' ' -f 2 )"

    local startLineSelectGroup="$( getLineNo ${startNodeSelectGroup} 1 )"
    local endLineSelectGroup="$(   getLineNo ${endNodeSelectGroup} 9 )"

    local endLineHeader="$(( ${startLineSelectGroup} - 1 ))"
    local startLineFooter="$(( ${endLineSelectGroup} + 1 ))"

    (
      if [[ ${indexNo} -eq 1 ]]; then
        printf '' > "${tmpfileHeader}"
      else
        getCachedLines "1" "${endLineHeader}" > "${tmpfileHeader}"
      fi
      wait
    )
    (
      if [[ ${indexNo} -eq 1 ]] ; then
        getCachedLines "1" "${endLineSelectGroup}" > "${tmpfileSelect}"
      else
        if [[ ${indexNo} -eq ${maxNodeCnt} ]] ; then
          getCachedLines "${startLineSelectGroup}" "${maxLineCnt}" > "${tmpfileSelect}"
        else
          getCachedLines "${startLineSelectGroup}" "${endLineSelectGroup}" > "${tmpfileSelect}"
        fi
      fi
      wait
    )
    (
      if [[ ${indexNo} -eq ${maxNodeCnt} ]] ; then
        printf '' > "${tmpfileFooter}"
      else
        getCachedLines "${startLineFooter}" "${maxLineCnt}" > "${tmpfileFooter}"
      fi
      wait
    )

    local titleLine="$(cat ${tmpfileSelect} | head -n 1)"
    local content="$(tail -n +2 ${tmpfileSelect} | sed -E 's/^\.+\t.+//g')"

    echo -e "${titleLine}\n${content}" > "${tmpfileSelect}"
    sed -i -e '$a\' "${tmpfileSelect}" #編集の結果末尾に改行がない場合'
    
    cat "${tmpfileHeader}" "${tmpfileSelect}" "${tmpfileFooter}" > "${inputFile}"
    invalidateCache

    bash "${0}" "${inputFile}" 't'
    exit 0
  }
}

: "バックアップ関数" && {
  ##############################################################################
  # バックアップ作成
  # 引数:なし(グローバルのみ)
  ##############################################################################
  function makeBackup {
    local orgFile="${inputFile}"
    local MAX_BACKUP_COUNT=3
  
    #3つ以上作る気がない
    #echo 'バックアップ作成'
    if [[ -f "./$(basename ${orgFile})_bk_2" ]] ; then 
      cp -f "./$(basename ${orgFile})_bk_2" "./$(basename ${orgFile})_bk_3"
    fi
    if [[ -f "./$(basename ${orgFile})_bk_1" ]] ; then 
      cp -f "./$(basename ${orgFile})_bk_1" "./$(basename ${orgFile})_bk_2"
    fi
    cp -f "./$(basename ${orgFile})" "./$(basename ${orgFile})_bk_1"
  }
}

: "初期処理" && {
  ##############################################################################
  # 初期処理
  ##############################################################################
  function myInit {

    #横幅取得
    maxRowLength="$( tput cols )"

    #ノード情報検出
    detectNode
    
    #指定ファイルがノード情報を持っていなかった場合、追加する。
    if [[ ${maxNodeCnt} -eq 0 ]] ; then
      echo 'ノードがありません。先頭に第一ノードを追加します' 
      sed -i -e '1s|^|.\t1st Node\n|g' "${inputFile}"
      invalidateCache
      read -s -n 1 c
      bash "${0}" "${inputFile}" 't'
      exit 0
    fi

    #全体文字数(ノードタイトル行と空行を除く)のカウント
    local allContentLines=""
    for line in "${fileLines[@]}"; do
      if [[ ! "${line}" =~ ^\. ]]; then
        allContentLines+="${line}"
      fi
    done
    allCharCount="${#allContentLines}"


    #エディタの設定
    #editorList配列の優先順で存在するコマンドに決定される。
    #ユーザによる書き換えも想定
    #(selected_editor部分を任意のエディター起動コマンドに変更)
    editorList=("${selected_editor}" 'edit' 'micro' 'nano' 'vi' 'ed')
    for itemE in "${editorList[@]}" ; do
      #コマンドがエラーを返すか否かで判断
      \command -v "${itemE}" >/dev/null 2>&1
      if [[ ${?} = 0 ]] ; then
        selected_editor="${itemE}"
        break
      fi
    done

    #ビューワの設定
    #viewerList配列の優先順で存在するコマンドに決定される。
    #ユーザによる書き換えも想定
    #(selected_viewer部分を任意のビューワ起動コマンドに変更)
    viewerList=("${selected_viewer}" 'less' 'more' 'view' 'cat')
    for itemV in "${viewerList[@]}" ; do
      #コマンドがエラーを返すか否かで判断
      \command -v "${itemV}" >/dev/null 2>&1
      if [[ ${?} = 0 ]] ; then
        selected_viewer="${itemV}"
        break
      fi
    done

    ################################################
    # 動作指定の読み替え
    ################################################

    #(存在する)ファイルのみを指定した場合、ツリービューに読み替え
    if [[ ${#action} = 0 ]] ; then
      echo "動作指定がないためツリー表示します"
      read -s -n 1 c
      bash "${0}" "${inputFile}" 't'
      exit 0
    fi

    #動作指定を省略して段落を指定した場合、編集に読み替え
    if [[ ${action} =~ ^[0-9]+$ ]] && [[ ${#indexNo} = 0 ]] ; then
      echo "段落のみが指定されたため、編集モードにします"
      read -s -n 1 c
      bash "${0}" "${inputFile}" 'e' "${action}"
      exit 0
    fi

    if [[ -f ${inputFile} ]] && [[ ${#action} = 0 ]] ; then
      bash "${0}" "${inputFile}" 't'
      exit 0
    fi

    if [[ ${action} = 'ta' ]] && [[ ${maxRowLength} -le 50 ]] ; then
      if [[ ${maxRowLength} -le 40 ]] ; then
        echo "画面の横幅が足りないため表示を縮退します"
        read -s -n 1 c
        bash "${0}" "${inputFile}" 't'
        exit 0
      else
        echo "画面の横幅が足りないため表示を縮退します"
        read -s -n 1 c
        bash "${0}" "${inputFile}" 'tl'
        exit 0
      fi
    fi
    if [[ ${action} = 'tl' ]] && [[ ${maxRowLength} -le 40 ]] ; then
      echo "画面の横幅が足りないため表示を縮退します"
      read -s -n 1 c
      bash "${0}" "${inputFile}" 't'
      exit 0
    fi

    ######################################
    #バックアップ作成
    ######################################
    makeBackupActionList=('e' 'd' 'i' 'ie' 'ml' 'mr' 'md' 'mu' 'gml' 'gmr' 'gmu' 'gmd' 'c' 's')
    if arrayContains "${action}" "${makeBackupActionList[@]}"; then
      makeBackup
    fi

  }
}

: "パラメーターチェック" && {
  ##############################################################################
  # 引数:なし(グローバルのみ)
  # 戻り値:0(成功)/9(失敗)
  ##############################################################################
  function parameterCheck {
    
    local depth=$(getDepth ${indexNo})

    #動作指定のチェック
    allowActionList=('h' 'e' 'd' 'gd' 'i' 'ie' 't' 'tl' 'ta' 'f' 'fl' 'fa' 'v' 'gv' 'ml' 'mr' 'md' 'mu' 'gml' 'gmr' 'gmu' 'gmd' 'j' 'gj' 'c' 'gc' 's' 'o')
    if ! arrayContains "${action}" "${allowActionList[@]}"; then
      echo '引数2:無効なアクションです'
      read -s -n 1 c
      return 1
    fi

    unset allowActionList
    allowActionList=('e' 'd' 'gd' 'i' 'ie' 'f' 'fl' 'fa' 'v' 'gv' 'ml' 'mr' 'md' 'mu' 'gml' 'gmr' 'gmu' 'gmd' 'j' 'gj' 'c' 'gc' 's' 'o')
    if arrayContains "${action}" "${allowActionList[@]}"; then
      if [[ ${indexNo} = '' ]] ; then
        echo "ノードを指定してください"
        read -s -n 1 c
        return 1
      fi
    fi
    if arrayContains "${action}" "${allowActionList[@]}"; then
      if [[ ${indexNo} -le 0 ]] || [[ ${indexNo} -gt ${maxNodeCnt} ]] ; then
        echo "${indexNo}番目のノードは存在しません"
        read -s -n 1 c
        return 1
      fi
    fi

    #動作指定とノード番号のチェック(ノード状態の取得が必要なチェックは後続で実施)
    unset allowActionList
    allowActionList=('ml' 'gml')
    if arrayContains "${action}" "${allowActionList[@]}" && [[ ${depth} -le 1 ]] ; then
      echo "ノード番号${indexNo}はこれ以上浅く(左に移動)できません"
      read -s -n 1 c
      return 1
    fi

    unset allowActionList
    allowActionList=('mr' 'gmr')
    if arrayContains "${action}" "${allowActionList[@]}" && [[ ${depth} -ge 10 ]] ; then
      echo "ノード番号${indexNo}の深さは${depth}です。これ以上深く(右に移動)できません"
      read -s -n 1 c
      return 1
    fi

    unset allowActionList
    allowActionList=('mu' 'gmu')
    if arrayContains "${action}" "${allowActionList[@]}" && [[ ${indexNo} -eq 1 ]] ; then
      echo '引数2:1番目のノードは上に移動できません'
      read -s -n 1 c
      return 1
    fi

    unset allowActionList
    allowActionList=('md' 'gmd')
    if arrayContains "${action}" "${allowActionList[@]}" && [[ ${indexNo} -ge ${maxNodeCnt} ]] ; then
      echo "引数2:${indexNo}番目のノードは下に移動できません"
      read -s -n 1 c
      return 1
    fi

  }
}

: "一時ファイルにかかる処理" && {
  ##############################################################################
  # 一時ファイル削除
  # 引数:なし(グローバルのみ)
  # 戻り値:なし
  ##############################################################################
  function rm_tmpfile {
    [[ -f "${tmpfileSelect}" ]] && rm -f "${tmpfileSelect}"
    [[ -f "${tmpfileTarget}" ]] && rm -f "${tmpfileTarget}"
  }

  ##############################################################################
  # 一時ファイル作成
  # 引数:なし(グローバルのみ)
  # 戻り値:なし
  ##############################################################################
  function makeTmpfile {

    tmpfileSelect=$(mktemp)
    tmpfileTarget=$(mktemp)
    
    tmpContentHeader=""
    tmpContentFooter=""
    tmpContent1=""
    tmpContent2=""
  }
}

: "主処理" && {
  ##############################################################################
  # 主処理
  # 引数1:対象ファイルパス
  # 引数2:動作区分
  # 引数3:対象ノード番号
  # 引数4:動作区分に対するオプション指定
  # 戻り値:なし
  ##############################################################################
  function main {
    
    inputFile="${1}"
    action="${2}"
    indexNo="${3}"
    option="${4}"

    #対象ファイルの存在チェック
    if [[ ! -f ${inputFile} ]] ; then
      echo "${inputFile} なんてファイルないです"
      read -s -n 1 c
      exit 100
    fi

    # 初期処理
    myInit

    #パラメータチェック
    parameterCheck
    if [[ ${?} -ne 0 ]] ; then 
      exit 1
    fi

    makeTmpfile # 一時ファイルを作成

    char1="${action:0:1}"
    char2="${action:1:1}"
    char3="${action:2:1}"

    case "${char1}" in
      'o')  outputGroup "${option}"
            ;;
      's')  clear
            setSymbol
            ;;
      'j')  clear
            joinNode
            ;;
      'c')  clear
            switchProgress
            ;;
      'h')  clear
            displayHelp
            ;;
      't')  clear
            displayTree
            ;;
      'm')  case "${char2}" in 
              [ud]) clear
                    swapNode
                    ;;
              [lr]) clear
                    slideNode
                    ;;
              *)  echo 'err'
                  ;;
            esac
            ;;
      'g')  case "${char2}" in 
              'v')  clear
                    groupView
                    ;;
              'c')  dispGroupCharCount
                    ;;
              'd')  deleteGroup
                    ;;
              'j')  joinGroup
                    ;;
              *)  case "${char3}" in 
                    [ud]) clear
                          swapGroup
                          ;;
                    [lr]) clear
                          slideGroup
                          ;;
                    [lr]) clear
                          slideGroup
                          ;;
                    *)  echo 'err'
                        ;;
                  esac
            esac
            ;;
      'f')  clear
            focusMode
            ;;
      'i')  clear
            case "${char2}" in
              '') insertNode
                  ;;
              'e') insertEdit
                  ;;              
            esac
            ;;
      [edv])  clear
              singleNodeOperations
              ;;
      *) ;;
    esac
  }  
}

###########################################
# エントリーポイント
###########################################
main "${1}" "${2}" "${3}" "${4}"

# 正常終了したときに一時ファイルを削除する
trap rm_tmpfile EXIT
# 異常終了したときに一時ファイルを削除する
trap 'trap - EXIT; rm_tmpfile; exit -1' INT PIPE TERM
