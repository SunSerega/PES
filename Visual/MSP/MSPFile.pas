unit MSPFile;

uses System.Windows;
uses System.Windows.Controls;
uses System.Windows.Media;

uses VUtils           in '..\VUtils';

uses MinimizableCore  in '..\..\Backend\MinimizableCore';
uses MFile            in '..\..\Backend\Minimizables\MFile';

uses MSPStandard;

type
  
  FileMSP = sealed class(StandardMSP)
    
    protected function MakeMinimizable(dir: string): MinimizableList; override :=
    new MFileBatch(dir);
    
    protected property Description: string read 'Line removal'; override;
    
  end;
  
end.