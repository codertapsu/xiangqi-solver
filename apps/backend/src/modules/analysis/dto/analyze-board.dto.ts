import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsEnum,
  IsInt,
  IsNumber,
  IsOptional,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export enum AiProviderEnum {
  gemini = 'gemini',
  openai = 'openai',
  mock = 'mock',
}

export enum EngineProviderEnum {
  pikafish = 'pikafish',
  mock = 'mock',
}

export enum SideToMoveEnum {
  red = 'red',
  black = 'black',
  unknown = 'unknown',
}

export enum LanguageEnum {
  en = 'en',
  vi = 'vi',
  zh = 'zh',
}

export enum PieceColorEnum {
  red = 'red',
  black = 'black',
}

export enum PieceTypeEnum {
  king = 'king',
  advisor = 'advisor',
  elephant = 'elephant',
  horse = 'horse',
  rook = 'rook',
  cannon = 'cannon',
  pawn = 'pawn',
}

/** A single board piece in request bodies. */
export class BoardPieceDto {
  @ApiProperty({ enum: PieceColorEnum })
  @IsEnum(PieceColorEnum)
  color!: PieceColorEnum;

  @ApiProperty({ enum: PieceTypeEnum })
  @IsEnum(PieceTypeEnum)
  type!: PieceTypeEnum;

  @ApiProperty({ minimum: 0, maximum: 8, description: 'File 0..8 (0 = Red far-left).' })
  @IsInt()
  @Min(0)
  @Max(8)
  file!: number;

  @ApiProperty({ minimum: 0, maximum: 9, description: 'Rank 0..9 (0 = Red home).' })
  @IsInt()
  @Min(0)
  @Max(9)
  rank!: number;

  @ApiProperty({ required: false, minimum: 0, maximum: 1 })
  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(1)
  confidence?: number;
}

/** Body for POST /api/analysis/board (bypasses vision, runs engine directly). */
export class AnalyzeBoardDto {
  @ApiProperty({ required: false, enum: AiProviderEnum })
  @IsOptional()
  @IsEnum(AiProviderEnum)
  provider?: AiProviderEnum;

  @ApiProperty({ enum: SideToMoveEnum })
  @IsEnum(SideToMoveEnum)
  sideToMove!: SideToMoveEnum;

  @ApiProperty({ type: [BoardPieceDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(32)
  @ValidateNested({ each: true })
  @Type(() => BoardPieceDto)
  pieces!: BoardPieceDto[];

  @ApiProperty({ required: false, enum: EngineProviderEnum })
  @IsOptional()
  @IsEnum(EngineProviderEnum)
  engineProvider?: EngineProviderEnum;

  @ApiProperty({ required: false, minimum: 1, maximum: 30 })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(30)
  engineDepth?: number;

  @ApiProperty({ required: false, minimum: 50, maximum: 60000 })
  @IsOptional()
  @IsInt()
  @Min(50)
  @Max(60000)
  engineMoveTimeMs?: number;

  @ApiProperty({ required: false, minimum: 1, maximum: 1024, description: 'Pikafish Threads.' })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(1024)
  engineThreads?: number;

  @ApiProperty({ required: false, minimum: 1, maximum: 32768, description: 'Pikafish Hash (MB).' })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(32768)
  engineHashMb?: number;

  @ApiProperty({ required: false, minimum: 1, maximum: 10, description: 'Top-N moves (MultiPV).' })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(10)
  engineMultiPv?: number;

  @ApiProperty({ required: false, enum: LanguageEnum, description: 'Move-notation language.' })
  @IsOptional()
  @IsEnum(LanguageEnum)
  language?: LanguageEnum;
}
