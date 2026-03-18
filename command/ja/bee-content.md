クリエイター ↔ レビュアーのコンテンツ品質ループ（bee-content）をtmuxで起動します。

## 実行手順

### ステップ0：対話形式でセットアップ

まず `$ARGUMENTS` を解析し、不足している値をtmux起動前に対話形式で確認します。

#### 0a. $ARGUMENTSの解析

- **instruction**: 最初の `--` フラグより前のすべて（フラグがない場合は文字列全体）
- **--criteria "..."**: 品質基準
- **--threshold N**: 採用スコアの閾値（整数）
- **--max-loops N**: 最大ループ回数（整数）
- **--count N**: 生成するコンテンツ数（整数、2以上でバッチモード）
- **--name <name>**: セッション名（後で再開するため）

#### 0b. 不足している値を対話形式で確認（デフォルトを黙って使わず、必ず聞く）

不足している値を順番に `AskUserQuestion` で確認します：

**1. 指示内容**（$ARGUMENTSに含まれていない場合）:
```
どんなコンテンツを作成しますか？
```

**2. 評価基準**（--criteriaで明示されていない場合は常に確認）:
```
このコンテンツの品質基準を教えてください。
例: "技術的に正確、コード例を含む、800字以内"
   "魅力的な見出し、明確な価値提案、専門用語なし"
（Enterを押すとデフォルト: "高品質で正確、読みやすく構造化されたコンテンツ"を使用）
```
空回答またはEnterの場合はデフォルト `"高品質で正確、読みやすく構造化されたコンテンツ"` を使用。

**3. 採用スコアの閾値**（--thresholdで指定されていない場合）:
```
何点以上で採用しますか？（0-100、デフォルト: 80）
```
空回答の場合は `80` を使用。

**4. 最大ループ回数**（--max-loopsで指定されていない場合）:
```
クリエイター ↔ レビュアーのループは最大何回ですか？（デフォルト: 3）
```
空回答の場合は `3` を使用。

#### 0c. 生成件数（--countで指定されていない場合）:
```
コンテンツを何件生成しますか？（デフォルト: 1）
```
空回答の場合は `1` を使用（後方互換の単体モード）。

#### 0d. セッション名（--nameが指定されていない場合は常に確認）:
```
後で再開するためにセッション名を付けますか？（Enterでスキップ、タイムスタンプを使用）
```
空回答の場合はタイムスタンプを使用（ステップ2で自動設定）。

全ての値が揃ったら内容を表示して確認を取ります：
```
bee-content を開始します：
  指示内容:   {INSTRUCTION}
  評価基準:   {CRITERIA}
  採用閾値:   {THRESHOLD}/100
  最大ループ: {MAX_LOOPS}回
  生成件数:   {COUNT}件

開始しますか？ (Y/n)
```
n または no の場合はここで終了します。

#### 再開モード

`--name <name>` が指定されていて `.beeops/tasks/content/<name>` が存在する場合、代わりに再開プロンプトを表示します：
```
セッション '<name>' を再開しますか？
  承認済み: {state.yamlのapproved}/{state.yamlのcount}件
  ループ:   {state.yamlのcurrent_loop}回目
  タスク:   {instruction.txtの先頭60文字}
再開しますか？ (Y/n)
```
`approved`、`current_loop`、`count` は `.beeops/tasks/content/<name>/state.yaml` から読み取ります。
指示内容のプレビューは `.beeops/tasks/content/<name>/instruction.txt` から読み取ります。
Yの場合、ステップ2の初期化をスキップして既存のタスクディレクトリを使用してステップ3に進みます。

### ステップ1：パッケージパスの解決

```bash
PKG_DIR=$(node -e "console.log(require.resolve('beeops/package.json').replace('/package.json',''))")
BO_SCRIPTS_DIR="$PKG_DIR/scripts"
BO_CONTEXTS_DIR="$PKG_DIR/contexts"
```

### ステップ2：タスクディレクトリとファイルの作成

```bash
# 指定された名前またはタイムスタンプを使用
TASK_ID="${NAME:-$(date +%Y%m%d-%H%M%S)}"
TASK_DIR=".beeops/tasks/content/$TASK_ID"

# 再開でない場合のみ初期化
mkdir -p "$TASK_DIR/items/pending" "$TASK_DIR/items/approved" "$TASK_DIR/items/rejected"
mkdir -p "$TASK_DIR/reviews" "$TASK_DIR/prompts"
echo "$INSTRUCTION" > "$TASK_DIR/instruction.txt"
echo "$CRITERIA" > "$TASK_DIR/criteria.txt"

# state.yaml（新規セッションのみ）
cat > "$TASK_DIR/state.yaml" <<EOF
name: ${TASK_ID}
count: ${COUNT}
approved: 0
current_loop: 0
EOF
```

### ステップ3：bo tmuxセッションの確認・作成

```bash
SESSION="bee-content"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  CWD=$(pwd)
  tmux new-session -d -s "$SESSION" -c "$CWD"
  tmux set-option -t "$SESSION" pane-border-status top
  tmux set-option -t "$SESSION" pane-border-format \
    " #{?pane_active,#[bold],}#{?@agent_label,#{@agent_label},#{pane_title}}#[default] "
fi
```

### ステップ4：tmuxウィンドウの作成とループの起動

```bash
tmux new-window -t "$SESSION" -n "content-$TASK_ID" \
  "BO_CONTEXTS_DIR='$BO_CONTEXTS_DIR' BO_SCRIPTS_DIR='$BO_SCRIPTS_DIR' bash '$BO_SCRIPTS_DIR/launch-content-loop.sh' '$TASK_ID' '$TASK_DIR' '$THRESHOLD' '$MAX_LOOPS' '$COUNT'; echo '--- 完了（Enterを押してください）---'; read"

# ペイン0（オーケストレーター）のタイトル設定
tmux select-pane -t "$SESSION:content-$TASK_ID.0" -T "🐝 content-$TASK_ID"
tmux set-option -p -t "$SESSION:content-$TASK_ID.0" @agent_label "🐝 content-$TASK_ID" 2>/dev/null || true
tmux set-option -p -t "$SESSION:content-$TASK_ID.0" allow-rename off 2>/dev/null || true
tmux set-option -p -t "$SESSION:content-$TASK_ID.0" pane-border-style "fg=yellow" 2>/dev/null || true
```

### ステップ5：tmuxセッションへの自動接続

```bash
case "$(uname -s)" in
  Darwin)
    osascript -e '
    tell application "Terminal"
      activate
      do script "tmux attach -t bee-content"
    end tell
    ' 2>/dev/null || echo "新しいターミナルを開いて実行してください: tmux attach -t bee-content"
    ;;
  *)
    echo "コンテンツループを開始しました。接続: tmux attach -t bee-content"
    ;;
esac
```

macOSでは、Terminal.appを自動的に開いてtmuxセッションに接続します。
その他のプラットフォームでは、接続コマンドを表示します。

### ステップ6：ステータスメッセージの表示

COUNTに応じて以下をユーザーに表示してください：

**COUNT=1（単体モード）の場合:**
```
bee-content を開始しました。
  task_id:   {TASK_ID}
  threshold: {THRESHOLD}/100
  max_loops: {MAX_LOOPS}
  output:    {TASK_DIR}/content.md

  モニター: tmux attach -t bee-content
  停止:     tmux kill-window -t bee-content:content-{TASK_ID}
  再開:     /bee-content --name {TASK_ID}
```
「再開」行は名前付きセッション（タイムスタンプ以外）の場合のみ表示。

**COUNT>=2（バッチモード）の場合:**
```
bee-content を開始しました。
  task_id:   {TASK_ID}
  count:     {COUNT}件
  threshold: {THRESHOLD}/100
  max_loops: {MAX_LOOPS}
  output:    {TASK_DIR}/items/approved/

  モニター: tmux attach -t bee-content
  停止:     tmux kill-window -t bee-content:content-{TASK_ID}
  再開:     /bee-content --name {TASK_ID}
```
「再開」行は名前付きセッションの場合のみ表示。

## 注意事項

- `$ARGUMENTS` はスラッシュコマンドの引数を含みます
- このコマンドは**対象プロジェクトディレクトリ**で実行する必要があります
- COUNT=1: コンテンツは `.beeops/tasks/content/{task_id}/content.md` に書き込まれます（後方互換）
- COUNT>=2: 承認されたコンテンツは `.beeops/tasks/content/{task_id}/items/approved/` に書き込まれます
- 各ループ：クリエイターが書く → レビュアーが審査 → スコアを閾値と比較
- ループログ：`.beeops/tasks/content/{task_id}/loop.log`
- セッション状態：`.beeops/tasks/content/{task_id}/state.yaml`
