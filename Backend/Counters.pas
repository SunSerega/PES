unit Counters;

type
  
  Counter = abstract class
    
    public event ValueChanged: procedure(new_v: real);
    protected procedure InvokeValueChanged(new_v: real);
    begin
      {$ifdef DEBUG}
      if not new_v.InRange(0,1) then raise new System.ArgumentException($'new_v = {new_v}');
      {$endif DEBUG}
      var ValueChanged := ValueChanged;
      if ValueChanged=nil then exit;
      ValueChanged(new_v);
    end;
    
  end;
  
  SubCounter = abstract class(Counter)
    
    public procedure ExecuteBase; abstract;
    
  end;
  
  ManualProcCounter = class(SubCounter)
    private work: Action<real->()>;
    
    public constructor(work: Action<real->()>) := self.work := work;
    protected constructor := raise new System.InvalidOperationException;
    
    public procedure ExecuteBase; override :=
    work(self.InvokeValueChanged);
    
  end;
  ManualFuncCounter<T> = class(SubCounter)
    private work: Func<real->(), T>;
    
    private res: T;
    public property Result: T read res;
    
    public constructor(work: Func<real->(), T>) := self.work := work;
    protected constructor := raise new System.InvalidOperationException;
    
    public procedure ExecuteBase; override :=
    self.res := work(self.InvokeValueChanged);
    
  end;
  
  MultiCounter = class(SubCounter)
    private count: integer;
    private make_work: integer->SubCounter;
    
    public constructor(count: integer; make_work: integer->SubCounter);
    begin
      self.count := count;
      self.make_work := make_work;
    end;
    public static function FromCollection<T>(coll: ICollection<T>; make_work: T->SubCounter): MultiCounter;
    begin
      var enmr: IEnumerator<T> := coll.GetEnumerator();
      Result := new MultiCounter(coll.Count, i->
      begin
        if not enmr.MoveNext then raise new System.InvalidOperationException;
        Result := make_work(enmr.Current);
      end);
    end;
    protected constructor := raise new System.InvalidOperationException;
    
    public procedure ExecuteBase; override :=
    for var i := 0 to count-1 do
    begin
      var work := make_work(i);
      work.ValueChanged += sub_v->
        self.InvokeValueChanged((i+sub_v)/count);
      work.ExecuteBase;
      self.InvokeValueChanged((i+1)/count);
    end;
    
  end;
  
end.