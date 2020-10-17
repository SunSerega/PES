unit ThreadUtils;

uses System.Threading;

uses PersentDone;

type
  
  SimpleTask<TRes> = sealed class
    private thr: Thread;
    private res: TRes;
    private e: Exception;
    
    public constructor(f: ()->TRes);
    begin
      self.thr := new Thread(()->
      try
        self.res := f();
      except
        on e: Exception do
        begin
//          Writeln(e.ToString);
          self.e := e;
        end;
      end);
      thr.IsBackground := true;
      thr.Start;
    end;
    
    public function Join: TRes;
    begin
      thr.Join;
      if e<>nil then
        System.Runtime.ExceptionServices
        .ExceptionDispatchInfo.Capture(e).Throw;
      Result := self.res;
    end;
    
    public static function ExecMany<T>(counter: PersentDoneCounter; a: array of T; make_task: (T, PersentDoneCounter)->SimpleTask<TRes>): array of TRes;
    begin
      var max_batch := System.Environment.ProcessorCount+1;
      var a_enmr: IEnumerator<T> := a.AsEnumerable.GetEnumerator;
      
      var tsks := new Queue<SimpleTask<TRes>>(max_batch);
      var res := new TRes[a.Length];
      Result := res;
      
      counter.SplitTasks(a.Length, (i, counter)->
      begin
        if a_enmr<>nil then loop max_batch-tsks.Count do
          if a_enmr.MoveNext then
            tsks.Enqueue(make_task(a_enmr.Current, counter)) else
          begin
            a_enmr := nil;
            break;
          end;
        
        res[i] := tsks.Dequeue.Join;
      end);
      
    end;
    
  end;

end.