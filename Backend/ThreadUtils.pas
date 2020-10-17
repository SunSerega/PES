unit ThreadUtils;

uses System.Threading;

uses PersentDone;

var MaxThreadBatch := System.Environment.ProcessorCount+1;

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
      if a.Length=0 then
      begin
        counter.ManualAddValue(1);
        exit;
      end;
      
      var a_enmr: IEnumerator<T> := a.AsEnumerable.GetEnumerator;
      
      var tasks := new Queue<SimpleTask<TRes>>(Min(MaxThreadBatch, a.Length));
      var res := new TRes[a.Length];
      Result := res;
      
      counter.SplitTasks(a.Length, (i, counter)->
      begin
        if a_enmr<>nil then loop MaxThreadBatch-tasks.Count do
          if a_enmr.MoveNext then
            tasks.Enqueue(make_task(a_enmr.Current, counter)) else
          begin
            a_enmr := nil;
            break;
          end;
        
        res[i] := tasks.Dequeue.Join;
      end);
      
    end;
    
  end;

//ToDo #2327
    {public static }function ExecMany<T, TRes>(sq: sequence of T; make_task: T->SimpleTask<TRes>; halt_switch: System.Threading.CancellationToken): sequence of TRes;
    begin
      var sq_enmr: IEnumerator<T> := sq.GetEnumerator;
      var tasks := new Queue<SimpleTask<TRes>>(MaxThreadBatch);
      
      while true do
      begin
        if sq_enmr<>nil then
          while tasks.Count < MaxThreadBatch do
            if halt_switch.IsCancellationRequested or not sq_enmr.MoveNext then
            begin
              sq_enmr := nil;
              break;
            end else
            begin
              var new_tsk := make_task(sq_enmr.Current);
              if new_tsk<>nil then
                tasks.Enqueue(new_tsk) else
//                while tasks.Count <> 0 do
//                  yield tasks.Dequeue.Join;
            end;
        
        if tasks.Count=0 then break;
        yield tasks.Dequeue.Join;
      end;
      
    end;
    
end.