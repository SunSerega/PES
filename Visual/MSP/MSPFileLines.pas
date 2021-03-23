unit MSPFileLines;

uses System.Windows;
uses System.Windows.Controls;
uses System.Windows.Media;

uses VUtils           in '..\VUtils';

uses MinimizableCore  in '..\..\Backend\MinimizableCore';
uses MFileLines       in '..\..\Backend\Minimizables\MFileLines';

uses MSPStandard;

type
  
  FileLinesMSP = sealed class(StandardMSP)
    
    protected function MakeMinimizable(dir, target: string): MinimizableContainer; override :=
    new MFileBatch(dir, target);
    
    protected property Description: string read 'Line removal'; override;
    
  end;
  
end.