library PESToolKit;

uses SettingData in 'Backend\SettingData';
uses Testing in 'Backend\Testing';

type
  Settings = SettingData.Settings;
  
  CompResult = Testing.CompResult;
  ExecResult = Testing.ExecResult;
  
procedure Init;
begin
  var a := System.Reflection.Assembly.GetExecutingAssembly;
  foreach var t in a.GetTypes do
  begin
    var m := t.GetMethod('$Initialization');
    if m=nil then continue;
    m.Invoke(nil,nil);
  end;
end;

end.