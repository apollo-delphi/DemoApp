unit Unit1;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.UI.Intf,
  FireDAC.Phys.Intf, FireDAC.Stan.Def, FireDAC.Stan.Pool, FireDAC.Stan.Async,
  FireDAC.Phys, FireDAC.Phys.FB, FireDAC.Phys.FBDef, FireDAC.FMXUI.Wait,
  Data.DB, FireDAC.Comp.Client, FMX.Memo.Types, FMX.ScrollBox, FMX.Memo,
  FMX.Controls.Presentation, FMX.StdCtrls, FireDAC.Stan.Param, FireDAC.DatS,
  FireDAC.DApt.Intf, FireDAC.DApt, FireDAC.Comp.DataSet, FMX.Edit,
  FireDAC.Comp.BatchMove, FMX.TMSFNCTypes, FMX.TMSFNCUtils, FMX.TMSFNCGraphics,
  FMX.TMSFNCGraphicsTypes, FMX.TMSFNCGridCell, FMX.TMSFNCGridOptions,
  FMX.TMSFNCCustomControl, FMX.TMSFNCCustomScrollControl, FMX.TMSFNCGridData,
  FMX.TMSFNCCustomGrid, FMX.TMSFNCGrid, FMX.TMSFNCCustomComponent,
  FMX.TMSFNCGridDatabaseAdapter;

type
  TDemoForm = class(TForm)
    FDConnection: TFDConnection;
    FDQuery: TFDQuery;
    btnImportData: TButton;
    lbHost: TLabel;
    edHost: TEdit;
    lbDatabase: TLabel;
    edDatabase: TEdit;
    btnConnect: TButton;
    lbConnectionState: TLabel;
    FDBatchMove: TFDBatchMove;
    TMSFNCGrid1: TTMSFNCGrid;
    TMSFNCGridDatabaseAdapter1: TTMSFNCGridDatabaseAdapter;
    DataSource: TDataSource;
    FDData: TFDQuery;
    FDEventAlerter: TFDEventAlerter;
    procedure btnImportDataClick(Sender: TObject);
    procedure btnConnectClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FDEventAlerterAlert(ASender: TFDCustomEventAlerter;
      const AEventName: string; const AArgument: Variant);
  private
    function IsConnected: Boolean;
    function IsTableExists: Boolean;
    function GetParamsFilePath: string;
    procedure ConnectToDB;
    procedure DisconnectDB;
    procedure ImportData;
    procedure ReadParams;
    procedure SaveParams;
    procedure UpdateConnectionCaption;
  public
    { Public declarations }
  end;

var
  DemoForm: TDemoForm;

implementation

{$R *.fmx}

uses
  FireDAC.Comp.BatchMove.Text,
  FireDAC.Comp.BatchMove.DataSet,
  System.IOUtils;

procedure TDemoForm.btnConnectClick(Sender: TObject);
begin
  if not IsConnected then
    ConnectToDB
  else
    DisconnectDB;
end;

procedure TDemoForm.btnImportDataClick(Sender: TObject);
begin
  ImportData;
end;

procedure TDemoForm.ConnectToDB;
begin
  FDConnection.Params.Clear;
  FDConnection.Params.Add('DriverID=FB');
  FDConnection.Params.Add('Host=' + edHost.Text);
  FDConnection.Params.Add('Database=' + edDatabase.Text);
  FDConnection.Params.Add('User_Name=SYSDBA');
  FDConnection.Params.Add('Password=masterkey');
  FDConnection.Open;

  FDData.SQL.Text := 'select * from ETB_SAN';

  FDEventAlerter.Names.Add('ViewChanged');
  FDEventAlerter.Options.Kind := 'Events';
  FDEventAlerter.Options.Synchronize := True;
  FDEventAlerter.Options.Timeout := 1000;
  FDEventAlerter.Active := True;

  SaveParams;
  UpdateConnectionCaption;

  if IsTableExists then
    FDData.Open;
end;

procedure TDemoForm.DisconnectDB;
begin
  FDConnection.Connected := False;
  UpdateConnectionCaption;
end;

procedure TDemoForm.FDEventAlerterAlert(ASender: TFDCustomEventAlerter;
  const AEventName: string; const AArgument: Variant);
begin
  FDData.Refresh;
end;

procedure TDemoForm.FormCreate(Sender: TObject);
begin
  UpdateConnectionCaption;
  ReadParams;
end;

function TDemoForm.GetParamsFilePath: string;
begin
  Result := TPath.Combine(GetCurrentDir, 'ConnectParams.ini');
end;

procedure TDemoForm.ImportData;
var
  StringList: TStringList;
  FieldArr: TArray<string>;
  FieldName: string;
  FieldsSQL: string;
  i: Integer;
  Reader: TFDBatchMoveTextReader;
  Writer: TFDBatchMoveDataSetWriter;
begin
  FDEventAlerter.Active := False;

  if not IsTableExists then
  begin
    StringList := TStringList.Create;
    try
      StringList.LoadFromFile(TPath.Combine(GetCurrentDir, 'ETB_SANs 10-07-2020.csv'));

      FieldArr := StringList.Strings[0].Split([',']);
      FieldsSQL := '';
      for i := 0 to Length(FieldArr) - 1 do
      begin
        if i > 0 then
          FieldsSQL := FieldsSQL + ',';
        FieldName := FieldArr[i];
        FieldsSQL := FieldsSQL + Format('%s %s', [FieldName, 'VARCHAR(1000)']);
      end;

      FDQuery.SQL.Text := Format('CREATE TABLE ETB_SAN (%s)', [FieldsSQL]);
      FDQuery.ExecSQL;
    finally
      StringList.Free;
    end;

    FDQuery.SQL.Clear;
    FDQuery.SQL.Add('CREATE TRIGGER TR_ETB_SAN FOR ETB_SAN');
    FDQuery.SQL.Add('ACTIVE AFTER INSERT OR UPDATE OR DELETE');
    FDQuery.SQL.Add('AS BEGIN');
    FDQuery.SQL.Add('POST_EVENT ''ViewChanged'';');
    FDQuery.SQL.Add('END');
    FDQuery.ExecSQL;
  end;

  FDBatchMove.Mode := dmAlwaysInsert;
  FDBatchMove.Options := [poClearDest];

  Reader := TFDBatchMoveTextReader.Create(FDBatchMove);
  Reader.FileName := TPath.Combine(GetCurrentDir, 'ETB_SANs 10-07-2020.csv');
  Reader.DataDef.Separator := ',';
  Reader.DataDef.WithFieldNames := False;

  Writer := TFDBatchMoveDataSetWriter.Create(FDBatchMove);
  Writer.DataSet := FDData;
  Writer.Optimise := False;

  FDBatchMove.GuessFormat;
  FDBatchMove.Execute;

  FDQuery.SQL.Text := 'DELETE FROM ETB_SAN WHERE SKU = ''sku''';
  FDQuery.ExecSQL;

  FDData.Open;
  FDData.Refresh;

  FDEventAlerter.Active := True;
end;

function TDemoForm.IsConnected: Boolean;
begin
  Result := FDConnection.Connected;
end;

function TDemoForm.IsTableExists: Boolean;
begin
  FDQuery.SQL.Text := 'select RDB$RELATION_NAME from RDB$RELATIONS ' +
    'where (RDB$SYSTEM_FLAG = 0) AND (RDB$RELATION_TYPE = 0) ' +
    'order by RDB$RELATION_NAME';
  FDQuery.Open;
  FDQuery.FetchAll;

  if not FDQuery.Eof then
    Result := True
  else
    Result := False;
end;

procedure TDemoForm.ReadParams;
var
  StringList: TStringList;
begin
  if TFile.Exists(GetParamsFilePath) then
  begin
    StringList := TStringList.Create;
    try
      StringList.LoadFromFile(GetParamsFilePath);

      edHost.Text := StringList.Values['host'];
      edDatabase.Text := StringList.Values['database'];
    finally
      StringList.Free;
    end;
  end
  else
  begin
    edHost.Text := 'localhost';
    edDatabase.Text := TPath.Combine(GetCurrentDir, 'DEMO.FDB');
  end;
end;

procedure TDemoForm.SaveParams;
var
  StringList: TStringList;
  FileStream: TFileStream;
begin
  if not TFile.Exists(GetParamsFilePath) then
  begin
    FileStream := TFile.Create(GetParamsFilePath);
    FileStream.Free;
  end;

  StringList := TStringList.Create;
  try
    StringList.Values['host'] := edHost.Text;
    StringList.Values['database'] := edDatabase.Text;

    StringList.SaveToFile(GetParamsFilePath);
  finally
    StringList.Free;
  end;
end;

procedure TDemoForm.UpdateConnectionCaption;
begin
  if IsConnected then
  begin
    lbConnectionState.Text := 'Connected';
    btnConnect.Text := 'Disconnect';
    btnImportData.Enabled := True;
  end
  else
  begin
    lbConnectionState.Text := 'Disconnected';
    btnConnect.Text := 'Connect';
    btnImportData.Enabled := False;
  end;
end;

end.
