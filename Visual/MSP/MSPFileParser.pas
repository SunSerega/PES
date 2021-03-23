unit MSPFileParser;

uses System.Windows;
uses System.Windows.Controls;
uses System.Windows.Media;

uses VUtils           in '..\VUtils';

uses MinimizableCore  in '..\..\Backend\MinimizableCore';
uses MFileParser      in '..\..\Backend\Minimizables\MFileParser';

uses MSPStandard;

type
  
  FileParserMSP = sealed class(StandardMSP)
    
    protected function MakeMinimizable(dir, target: string): MinimizableContainer; override :=
    new MFileBatch(dir, target);
    
    protected property Description: string read 'Line removal'; override;
    
  end;
  
end.