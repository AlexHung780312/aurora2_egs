1. 執行./run.sh --stage -2 會出現data目錄
2. 將目錄複製很多份，例如mas-heq_data和mas-nmf10_data，可以用這個指令
   cp -r data mas-heq_data
   cp -r data mas-nmf10_data
3. 刪除舊的data
   rm -rf data
4. 建立link，如果現在要處理mas-heq，就輸入
   ln -s mas-heq_data data
4. 處理特徵檔案，建立tmp.scp再跑combine_htk
5. 執行./run.sh --stage 0
6. 執行./run_dnn.sh

執行下一種特徵時要把link先刪除
   rm data
然後再跑combine_htk
