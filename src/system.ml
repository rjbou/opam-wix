type uuid_mode =
  | Rand
  | Exec of string * string * string option

type candle = {
  candle_wix_path : string;
  candle_files : string list;
}

type light = {
  light_wix_path : string;
  light_files : string list;
  light_exts : string list;
  light_out : string
}

type cygpath_out = [ `Win | `WinAbs | `Cyg | `CygAbs ]

type _ command =
  | Which : string command
  | Cygcheck : string command
  | Cygpath : (cygpath_out * string) command
  | Uuidgen : uuid_mode command
  | Candle : candle command
  | Light : light command

exception System_error of string

let call_inner : type a. a command -> a -> string * string list =
  fun command args -> match command, args with
  | Which, (path : string) ->
    "which", [ path ]
  | Cygcheck, path ->
    "cygcheck", [ path ]
  | Cygpath, (out, path) ->
    let opts = match out with
      | `Win -> "-w"
      | `WinAbs -> "-wa"
      | `Cyg -> "-u"
      | `CygAbs -> "-ua"
    in
    "cygpath", [ opts; path ]
  | Uuidgen, Rand ->
    "uuidgen", []
  | Uuidgen, Exec (p,e,v) ->
    "uuidgen", ["--md5"; "--namespace"; "@dns"; "--name";
      Format.sprintf "opam.%s.%s%s" p e
        (if v = None then "" else "."^ Option.get v)]
  | Candle, {candle_wix_path; candle_files} ->
    let candle = Filename.concat candle_wix_path "candle.exe" in
    candle, candle_files
  | Light, {light_wix_path;light_files;light_exts;light_out} ->
    let light = Filename.concat light_wix_path "light.exe" in
    let args =
      List.flatten (List.map (fun e -> ["-ext"; e]) light_exts)
      @ light_files @ ["-o"; light_out]
    in
    light, args


let gen_command_tmp_dir cmd =
  Printf.sprintf "%s-%06x" (Filename.basename cmd) (Random.int 0xFFFFFF)


let call : type a. a command -> a -> string list =
  fun command arguments ->
    let cmd, args = call_inner command arguments in
    let name = gen_command_tmp_dir cmd in
    let result = OpamProcess.run @@ OpamSystem.make_command ~name cmd args in
    let out = if OpamProcess.is_failure result then
        raise @@ System_error (Format.sprintf "%s" (OpamProcess.string_of_result result))
      else
        result.OpamProcess.r_stdout
    in
    OpamProcess.cleanup result;
    out

let call_unit : type a. a command -> a -> unit =
  fun command arguments ->
    let cmd, args = call_inner command arguments in
    let name = gen_command_tmp_dir cmd in
    let result = OpamProcess.run @@ OpamSystem.make_command ~name cmd args in
    (if OpamProcess.is_failure result then
      raise @@ System_error (Format.sprintf "%s" (OpamProcess.string_of_result result)));
    OpamProcess.cleanup result

let call_list : type a. (a command * a) list -> unit =
  fun commands ->
    let cmds = List.map (fun (cmd,args) ->
      let cmd, args = call_inner cmd args in
      let name = gen_command_tmp_dir cmd in
      OpamSystem.make_command ~name cmd args) commands
    in
    match OpamProcess.Job.(run @@ of_list cmds) with
    | Some (_,result) -> raise @@ System_error
      (Format.sprintf "%s" (OpamProcess.string_of_result result))
    | _ -> ()

let check_avalable_commands wix_path =
  call_list [
    Which, "cygcheck";
    Which, "cygpath";
    Which, "uuidgen";
    Which, Filename.concat wix_path "candle.exe";
    Which, Filename.concat wix_path "light.exe";
  ]

(* let windows_from_cygwin_path cygwin_disk path =
  match String.split_on_char '/' (String.trim path) with
  | ""::"cygdrive" :: disk :: rest ->
    let disk = String.uppercase_ascii disk ^ ":" in
    String.concat "\\" (disk::rest)
  | ""::rest ->
    String.concat "\\" (cygwin_disk :: "cygwin64" :: rest)
  | local ->
    let cwd = OpamFilename.cwd () in
    let path = Filename.concat (OpamFilename.Dir.to_string cwd) (String.concat "/" local) in
    (match String.split_on_char '/' path with
    | ""::rest | rest -> String.concat "\\" (cygwin_disk :: "cygwin64" :: rest))

 *)
let cyg_win_path out path = call Cygpath (out,path) |> List.hd |> String.trim
