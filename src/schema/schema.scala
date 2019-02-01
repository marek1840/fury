/*
  Fury, version 0.4.0. Copyright 2018-19 Jon Pretty, Propensive Ltd.

  The primary distribution site is: https://propensive.com/

  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
  in compliance with the License. You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required  by applicable  law or  agreed to  in writing,  software  distributed  under the
  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
  express  or  implied.  See  the  License for  the specific  language  governing  permissions and
  limitations under the License.
 */
package fury

import fury.error._
import Args._
import fury.layer.schema._
import guillotine._

import scala.util._

case class SchemaCtx(cli: Cli[CliParam[_]], layout: Layout, config: Config, layer: Layer)

object SchemaCli {

  def context(cli: Cli[CliParam[_]]) =
    for {
      layout <- cli.layout
      config <- fury.Config.read()(cli.env, layout)
      layer  <- Layer.read(Io.silent(config), layout.furyConfig, layout)
    } yield SchemaCtx(cli, layout, config, layer)

  def select(ctx: SchemaCtx) = {
    import ctx._
    for {
      cli      <- ctx.cli.hint(SchemaArg, ctx.layer.schemas.map(_.id))
      invoc    <- cli.read()
      io       <- invoc.io()
      schemaId <- invoc(SchemaArg)
      _ <- FurySchema.updateMainSchema(layer, schemaId) match {
            case Some(updatedLayer) => Layer.save(updatedLayer, layout)
            case _                  => Success(Unit)
          }
    } yield io.await()
  }

  def list(ctx: SchemaCtx) = {
    import ctx._
    for {
      cli       <- cli.hint(SchemaArg, layer.schemas.map(_.id))
      schemaArg <- ~cli.peek(SchemaArg).getOrElse(layer.main)
      schema    <- layer.schemas.findBy(schemaArg)
      cols      <- Success(Terminal.columns(cli.env).getOrElse(100))
      cli       <- cli.hint(RawArg)
      invoc     <- cli.read()
      io        <- invoc.io()
      raw       <- ~invoc(RawArg).isSuccess
      rows      <- ~layer.schemas.to[List]
      table     <- ~Tables(config).show(Tables(config).schemas(Some(schema.id)), cols, rows, raw)(_.id)
      _ <- ~(if (!raw)
               io.println(Tables(config).contextString(layout.pwd, layer.showSchema, schema)))
      _ <- ~io.println(UserMsg { theme =>
            table.mkString("\n")
          })
    } yield io.await()
  }

  def diff(ctx: SchemaCtx) = {
    import ctx._
    for {
      cli       <- ctx.cli.hint(SchemaArg, ctx.layer.schemas.map(_.id))
      cli       <- ctx.cli.hint(CompareArg, ctx.layer.schemas.map(_.id))
      cli       <- cli.hint(RawArg)
      invoc     <- cli.read()
      io        <- invoc.io()
      raw       <- ~invoc(RawArg).isSuccess
      schemaArg <- ~invoc(SchemaArg).toOption.getOrElse(layer.main)
      schema    <- layer.schemas.findBy(schemaArg)
      otherArg  <- invoc(CompareArg)
      other     <- layer.schemas.findBy(otherArg)
      cols      <- Success(Terminal.columns(cli.env).getOrElse(100))
      rows      <- ~Diff.gen[Schema].diff(schema, other)
      table <- ~Tables(config).show(
                  Tables(config).differences(schema.id.key, other.id.key),
                  cols,
                  rows,
                  raw)(_.label)
      _ <- ~(if (!raw)
               io.println(Tables(config).contextString(layout.pwd, layer.showSchema, schema)))
      _ <- ~io.println(UserMsg { theme =>
            table.mkString("\n")
          })
    } yield io.await()
  }

  def update(ctx: SchemaCtx) = {
    import ctx._
    for {
      cli      <- cli.hint(SchemaArg, layer.schemas.map(_.id))
      cli      <- cli.hint(SchemaNameArg)
      invoc    <- cli.read()
      io       <- invoc.io()
      newId    <- invoc(SchemaNameArg)
      schemaId <- ~invoc(SchemaArg).toOption.getOrElse(layer.main)
      force    <- ~invoc(ForceArg).toOption.isDefined
      layer    <- FurySchema.rename(layer, schemaId, newId, force)
      _        <- ~Layer.save(layer, layout)
    } yield io.await()
  }

  def add(ctx: SchemaCtx) = {
    import ctx._
    for {
      cli      <- cli.hint(SchemaArg, layer.schemas.map(_.id))
      cli      <- cli.hint(SchemaNameArg)
      invoc    <- cli.read()
      io       <- invoc.io()
      schemaId <- invoc(SchemaNameArg)
      layer <- invoc(SchemaArg) match {
                case Success(from) => FurySchema.clone(layer, from, schemaId)
                case _             => FurySchema.add(layer, schemaId)
              }
      _ <- ~Layer.save(layer, layout)
    } yield io.await()
  }

  def remove(ctx: SchemaCtx) = {
    import ctx._
    for {
      cli      <- cli.hint(SchemaArg, layer.schemas.map(_.id))
      invoc    <- cli.read()
      io       <- invoc.io()
      schemaId <- ~invoc(SchemaArg).toOption.getOrElse(layer.main)
      layer    <- FurySchema.remove(layer, schemaId)
      _        <- ~Layer.save(layer, layout)
    } yield io.await()
  }
}
