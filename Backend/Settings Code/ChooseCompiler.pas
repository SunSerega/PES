unit ChooseCompiler;
{$reference PresentationCore.dll}
{$reference PresentationFramework.dll}

uses System.Windows;
uses System.Windows.Controls;

type
  WindowChooseCompiler = sealed class(Window)
    
    public constructor(initial: sequence of string);
    begin
      self.Content := 'WindowChooseCompiler';
      //ToDo
    end;
    
    public function AskUser: array of string;
    begin
      Application.Create.Run(self);
      //ToDo
    end;
    
  end;
  
end.