(*
 * Copyright (c) 2013 Thomas Gazagnaire <thomas@gazagnaire.org>
 * Copyright (c) 2013 Anil Madhavapeddy <anil@recoil.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Rresult
open Astring

let err_cmdliner ?(usage=false) = function
  | Ok x -> `Ok x
  | Error s -> `Error (usage, s)

module type Monoid = sig
  type t
  val empty: t
  val union: t -> t -> t
end

(* {Misc informations} *)

module Name = struct

  let ocamlify s =
    let b = Buffer.create (String.length s) in
    String.iter begin function
      | 'a'..'z' | 'A'..'Z'
      | '0'..'9' | '_' as c -> Buffer.add_char b c
      | '-' -> Buffer.add_char b '_'
      | _ -> ()
    end s;
    let s' = Buffer.contents b in
    if String.length s' = 0 || ('0' <= s'.[0] && s'.[0] <= '9') then
      raise (Invalid_argument s);
    s'

  let ids = Hashtbl.create 1024

  let names = Hashtbl.create 1024

  let create name =
    let n =
      try 1 + Hashtbl.find ids name
      with Not_found -> 1 in
    Hashtbl.replace ids name n;
    Format.sprintf "%s%d" name n

  let find_or_create tbl key create_value =
    try Hashtbl.find tbl key
    with Not_found ->
      let value = create_value () in
      Hashtbl.add tbl key value;
      value

  let create key ~prefix =
    find_or_create names key (fun () -> create prefix)

end

module Codegen = struct

  let main_ml = ref None

  let generated_header () =
    let t = Unix.gettimeofday () in
    let months = [| "Jan"; "Feb"; "Mar"; "Apr"; "May"; "Jun";
                    "Jul"; "Aug"; "Sep"; "Oct"; "Nov"; "Dec" |] in
    let days = [| "Sun"; "Mon"; "Tue"; "Wed"; "Thu"; "Fri"; "Sat" |] in
    let time = Unix.gmtime t in
    let date =
      Format.sprintf "%s, %d %s %d %02d:%02d:%02d GMT"
        days.(time.Unix.tm_wday) time.Unix.tm_mday
        months.(time.Unix.tm_mon) (time.Unix.tm_year+1900)
        time.Unix.tm_hour time.Unix.tm_min time.Unix.tm_sec in
    Format.sprintf "Generated by %s (%s)."
      (String.concat ~sep:" " (Array.to_list Sys.argv))
      date

  let append oc fmt = Format.fprintf oc (fmt ^^ "@.")
  let newline oc = append oc ""

  let append_main fmt = match !main_ml with
    | None    -> failwith "main_ml"
    | Some oc -> append oc fmt

  let newline_main () = match !main_ml with
    | None    -> failwith "main_ml"
    | Some oc -> newline oc

  let set_main_ml file =
    let oc = Format.formatter_of_out_channel @@ open_out file in
    main_ml := Some oc

end

module Univ = struct

  type 'a key = string * ('a -> exn) * (exn -> 'a)

  let new_key: string -> 'a key =
    fun s (type a) ->
      let module M = struct
        exception E of a
      end
      in
      ( s
      , (fun a -> M.E a)
      , (function M.E a -> a | _ -> raise @@ Invalid_argument ("duplicate key: " ^ s))
      )

  module Map = Map.Make(String)

  type t = exn Map.t

  let empty = Map.empty

  let add (kn, kput, _kget) v t =
    Map.add kn (kput v) t

  let mem (kn, _, _) t =
    Map.mem kn t

  let find (kn, _kput, kget) t =
    if Map.mem kn t then Some (kget @@ Map.find kn t)
    else None

  let merge ~default m =
    let aux _k _def v = Some v in
    Map.union aux default m 
end
