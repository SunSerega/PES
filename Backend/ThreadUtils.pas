unit ThreadUtils;

uses System.Threading;

//uses Counters;

uses AQueue in '..\Utils\AQueue';

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
    end;
    
    public procedure Start := thr.Start;
    
    public function Join: TRes;
    begin
      thr.Join;
      if e<>nil then
        System.Runtime.ExceptionServices
        .ExceptionDispatchInfo.Capture(e).Throw;
      Result := self.res;
    end;
    
//    public static function ExecMany<T>(counter: PersentDoneCounter; a: array of T; make_task: (T, PersentDoneCounter)->SimpleTask<TRes>): array of TRes;
//    begin
//      if a.Length=0 then
//      begin
//        counter.ManualAddValue(1);
//        exit;
//      end;
//      
//      var a_enmr: IEnumerator<T> := a.AsEnumerable.GetEnumerator;
//      
//      var tasks := new Queue<SimpleTask<TRes>>(Min(MaxThreadBatch, a.Length));
//      var res := new TRes[a.Length];
//      Result := res;
//      
//      counter.SplitTasks(a.Length, (i, counter)->
//      begin
//        if a_enmr<>nil then loop MaxThreadBatch-tasks.Count do
//          if a_enmr.MoveNext then
//            tasks.Enqueue(make_task(a_enmr.Current, counter)) else
//          begin
//            a_enmr := nil;
//            break;
//          end;
//        
//        res[i] := tasks.Dequeue.Join;
//      end);
//      
//    end;
    
  end;
  
  //ToDo #2341
  TempContainer_2341<TRes> = sealed class
    new_tsk: SimpleTask<TRes>;
    res_q: AsyncQueue<SimpleTask<TRes>>;
    work: Func0<TRes>;
    
    function lambda: TRes;
    begin
      try
//        while new_tsk=nil do Sleep(1);
//        Writeln($'Started task {new_tsk.i}');
        Result := work();
//        Writeln($'Finished task {new_tsk.i}');
      finally
//        Writeln($'Enq''ed task {new_tsk.i}');
        res_q.Enq(new_tsk);
      end;
    end;
    
  end;
  
//ToDo #2327
    {public static }function ExecMany<T, TRes>(sq: sequence of T; make_work: T->Func0<TRes>; halt_switch: System.Threading.CancellationToken): sequence of TRes;
    begin
      var MaxThreadBatch := ThreadUtils.MaxThreadBatch;
      
      var sq_enmr: IEnumerator<T> := sq.GetEnumerator;
      var active_tasks := new List<SimpleTask<TRes>>(MaxThreadBatch);
      var res_q := new AsyncQueue<SimpleTask<TRes>>(MaxThreadBatch);
      
      while true do
      begin
        while active_tasks.Count < MaxThreadBatch do
          if halt_switch.IsCancellationRequested or (sq_enmr=nil) or not sq_enmr.MoveNext then
          begin
            sq_enmr := nil;
            break;
          end else
          begin
            var work := make_work(sq_enmr.Current);
            
            var temp := new TempContainer_2341<TRes>;
            temp.work := work;
            temp.res_q := res_q;
            temp.new_tsk := new SimpleTask<TRes>(temp.lambda);
//            Writeln($'Created task {temp.new_tsk.i}');
            //ToDo #2341
//            var new_tsk: SimpleTask<TRes>;
//            new_tsk := new SimpleTask<TRes>(()->
//            try
//              Result := work();
//            finally
//              res_q.Enq(new_tsk);
//            end);
            
            active_tasks += temp.new_tsk;
            temp.new_tsk.Start;
          end;
        
        if active_tasks.Count=0 then break;
//        Writeln($'Waiting on: {_ObjectToString(active_tasks.Select(tsk->tsk.i))}');
//        Writeln($'Waiting States: {_ObjectToString(active_tasks.Select(tsk->tsk.thr.ThreadState))}');
        if not res_q.MoveNext then raise new System.InvalidOperationException;
        
        var tsk := res_q.Current;
//        Writeln($'Deq''ed task {tsk.i}');
        if not active_tasks.Remove(tsk) then raise new System.InvalidOperationException;
        yield tsk.Join;
      end;
      
    end;
    
end.